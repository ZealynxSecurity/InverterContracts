// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

import {Test} from "forge-std/Test.sol";

// SuT

import {PP_Simple_v1AccessMock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Simple_v1AccessMock.sol";

import {
    PP_Simple_v1,
    IPaymentProcessor_v1
} from "src/modules/paymentProcessor/PP_Simple_v1.sol";

// Mocks
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {PP_Queue_v1Mock} from "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import "forge-std/console.sol";


contract PP_Queue_V1_Test is ModuleTest {
    // SuT
    PP_Simple_v1AccessMock paymentProcessor;

    PP_Queue_v1Mock queue;

    // Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

    //--------------------------------------------------------------------------
    // Events

    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );
    event UnclaimableAmountAdded(
        address indexed paymentClient,
        address indexed token,
        address indexed recipient,
        uint amount
    );
    // variable
    bytes32 public constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR";

    /// @dev    Flag positions in the flags byte.
    uint8 private constant FLAG_ORDER_ID = 0;
    uint8 private constant FLAG_START_TIME = 1;
    uint8 private constant FLAG_CLIFF_PERIOD = 2;
    uint8 private constant FLAG_END_TIME = 3;

    /// @dev    Timing skip reasons.
    uint8 private constant SKIP_NOT_STARTED = 1;
    uint8 private constant SKIP_IN_CLIFF = 2;
    uint8 private constant SKIP_EXPIRED = 3;

    //role
    bytes32 internal roleIDqueue;

    //address
    address admin;

    function setUp() public {
        admin = makeAddr("admin");
        admin = address(this);

        address impl2 = address(new PP_Queue_v1Mock());
        queue = PP_Queue_v1Mock(Clones.clone(impl2));
        _setUpOrchestrator(queue);
        _authorizer.setIsAuthorized(address(this), true);
        
        address impl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(impl));
        
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(queue), true);
        paymentClient.setToken(_token);

    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(
            address(queue.orchestrator()), address(_orchestrator)
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            queue.supportsInterface(
                type(IPaymentProcessor_v1).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        queue.init(_orchestrator, _METADATA, bytes(""));
    }

    function testQueueOperations() public {
        address recipient = makeAddr("recipient");
        
        // Configurar el token y los balances
        deal(address(_token), address(this), 1000 ether);
        _token.approve(address(queue), 1000 ether);
        
        // Setup una orden de pago básica
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            paymentToken: address(_token),
            amount: 100 ether,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Verificar que la cola está vacía inicialmente
        assertEq(queue.getQueueSize(address(this)), 0);
        
        // Añadir la orden a la cola usando la función expuesta del mock
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));
        
        // Verificar que la orden se añadió correctamente
        assertEq(queue.getQueueSize(address(this)), 1);
        
        // Verificar la cabeza de la cola
        uint headId = queue.getQueueHead(address(this));
        assertTrue(headId > 0);
        assertEq(headId, orderId, "El ID de la cabeza deberia coincidir con el ID retornado");
        
        // Obtener y verificar los detalles de la orden
        IPP_Queue_v1.QueuedOrder memory queuedOrder = queue.getOrder(headId);
        assertEq(queuedOrder.order.paymentToken, order.paymentToken);
        assertEq(queuedOrder.order.recipient, order.recipient);
        assertEq(queuedOrder.order.amount, order.amount);
        assertEq(uint(queuedOrder.state), uint(IPP_Queue_v1.RedemptionState.PROCESSING));
    }

    function testSimpleQueueOperations() public {
        // Crear una orden simple
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0x123),
            paymentToken: address(0x456),
            amount: 100,
            originChainId: 1,
            targetChainId: 1,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Añadir la orden
        uint id = queue.addOrder(order);
        assertEq(id, 1, "El primer ID deberia ser 1");

        // Obtener y verificar la orden
        IERC20PaymentClientBase_v1.PaymentOrder memory retrieved = queue.getOrder(id);
        assertEq(retrieved.recipient, order.recipient, "El recipient deberia coincidir");
        assertEq(retrieved.paymentToken, order.paymentToken, "El token deberia coincidir");
        assertEq(retrieved.amount, order.amount, "El amount deberia coincidir");
    }
}