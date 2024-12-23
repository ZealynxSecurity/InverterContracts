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

        address impl = address(new PP_Queue_v1Mock());
        queue = PP_Queue_v1Mock(Clones.clone(impl));
        _setUpOrchestrator(queue);
        _authorizer.setIsAuthorized(address(this), true);
        queue.init(_orchestrator, _METADATA, bytes(""));

        impl = address(new ERC20PaymentClientBaseV1Mock());
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

    function testQueueOperations(
        address recipient,
        uint96 amount
    ) public {
        // Ensure valid inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(queue));
        vm.assume(amount > 0 && amount < type(uint96).max);

        // Setup
        _authorizer.setIsAuthorized(address(queue), true);
        _token.mint(address(this), amount);
        _token.approve(address(queue), amount);

        // Create payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Add to queue and verify
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));
        assertEq(queue.getQueueSize(address(this)), 1, "Queue size should be 1");
        
        // Verify order details
        IPP_Queue_v1.QueuedOrder memory queuedOrder = queue.getOrder(orderId);
        assertEq(queuedOrder.order_.recipient, recipient, "Wrong recipient");
        assertEq(queuedOrder.order_.amount, amount, "Wrong amount");
        
        // Remove from queue and verify
        queue.exposed_removeFromQueue(orderId);
        assertEq(queue.getQueueSize(address(this)), 0, "Queue should be empty");
    }

    function test_validPaymentReceiver() public {
        // Test con dirección válida
        assertTrue(queue.exposed_validPaymentReceiver(makeAddr("valid")));
        
        // Test con dirección cero
        assertFalse(queue.exposed_validPaymentReceiver(address(0)));
        
        // Test con dirección del contrato
        assertFalse(queue.exposed_validPaymentReceiver(address(queue)));
    }

    function test_validTotalAmount() public {
        // Test con cantidad válida
        assertTrue(queue.exposed_validTotalAmount(100));
        
        // Test con cantidad cero
        assertFalse(queue.exposed_validTotalAmount(0));
    }

    function test_validTokenBalance() public {
        address user = makeAddr("user");
        
        // Configurar token y balances
        deal(address(_token), user, 1000);
        vm.startPrank(user);
        _token.approve(address(queue), 1000);
        vm.stopPrank();
        
        // Test con balance suficiente
        assertTrue(queue.exposed_validTokenBalance(address(_token), user, 500));
        
        // Test con balance insuficiente
        assertFalse(queue.exposed_validTokenBalance(address(_token), user, 2000));
    }

    function testFuzz_validTotalAmount(uint256 amount) public {
        if (amount == 0) {
            assertFalse(
                queue.exposed_validTotalAmount(amount),
                "Zero amount should be invalid"
            );
        } else {
            assertTrue(
                queue.exposed_validTotalAmount(amount),
                "Non-zero amount should be valid"
            );
        }
    }

    function testFuzz_validPaymentReceiver(address receiver) public {
        // Exclude special cases that should always be invalid
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(queue));
        vm.assume(receiver != address(_orchestrator));
        vm.assume(receiver != address(_orchestrator.fundingManager().token()));
        
        assertTrue(
            queue.exposed_validPaymentReceiver(receiver),
            "Valid receiver marked as invalid"
        );
    }

    function testFuzz_validTokenBalance(uint256 balance, uint256 amount) public {
        // Ensure amount is not zero as it's handled by validTotalAmount
        vm.assume(amount > 0);
        
        // Create test user and set up balance
        address user = makeAddr("user");
        deal(address(_token), user, balance);
        
        // Approve tokens for queue
        vm.startPrank(user);
        _token.approve(address(queue), amount);
        vm.stopPrank();
        
        // Check if balance is valid
        bool isValid = queue.exposed_validTokenBalance(
            address(_token),
            user,
            amount
        );
        
        if (balance >= amount) {
            assertTrue(isValid, "Sufficient balance marked as invalid");
        } else {
            assertFalse(isValid, "Insufficient balance marked as valid");
        }
    }

    function testFuzz_getPaymentQueueId(
        uint256 queueId,
        uint8 flagBits,
        uint8 dataLength
    ) public {
        // Bound the data length to reasonable values
        dataLength = uint8(bound(dataLength, 0, 10));
        
        // Create flags - we'll test both with and without the ORDER_ID bit
        bytes32 flags = bytes32(uint256(flagBits));
        
        // Create data array with fuzzed length
        bytes32[] memory data = new bytes32[](dataLength);
        if (dataLength > 0) {
            data[0] = bytes32(queueId);
        }
        
        uint256 retrievedId = queue.exposed_getPaymentQueueId(flags, data);
        
        // If ORDER_ID bit is set (bit 0) and we have data
        if ((flagBits & 1 == 1) && dataLength > 0) {
            assertEq(
                retrievedId,
                queueId,
                "Queue ID mismatch when flag is set and data exists"
            );
        } else {
            assertEq(
                retrievedId,
                0,
                "Should return 0 when flag is not set or data is empty"
            );
        }
    }


function testFuzz_AddPaymentOrder_Succeeds(
    address recipient,
    uint256 amount
) public {
    // Validaciones típicas de fuzz
    vm.assume(recipient != address(0));
    vm.assume(recipient != address(this));
    vm.assume(recipient != address(queue));
    vm.assume(amount > 0 && amount < 1e30); // Límite arbitrario

    // Prepara balances y allowance
    deal(address(_token), admin, amount);
    _token.approve(address(queue), amount);
    _authorizer.setIsAuthorized(address(queue), true);
    paymentClient.setIsAuthorized(address(queue), true);

    // Arma la orden
    IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
        recipient: recipient,
        paymentToken: address(_token),
        amount: amount,
        originChainId: block.chainid,
        targetChainId: block.chainid,
        flags: bytes32(0),
        data: new bytes32[](0)
    });
    assertEq(queue.getQueueSize(address(this)), 0);

    // Llamamos la exposed function
    uint newId = queue.exposed_addPaymentOrderToQueue(order, address(this));

    // Verificamos que se guardó
    IPP_Queue_v1.QueuedOrder memory qOrder = queue.getOrder(newId);
    assertEq(qOrder.order_.recipient, recipient, "Recipient mismatch");
    assertEq(qOrder.order_.amount, amount, "Amount mismatch");
    assertEq(uint(qOrder.state_), uint(IPP_Queue_v1.RedemptionState.PROCESSING), "State mismatch");
}

    function testFuzz_QueueOperations(
        address recipient,
        uint96 amount
    ) public {
        // Ensure valid inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(queue));
        vm.assume(amount > 0 && amount < type(uint96).max);

        // Setup
        _authorizer.setIsAuthorized(address(queue), true);
        paymentClient.setIsAuthorized(address(queue), true);
        deal(address(_token), address(this), amount);
        _token.approve(address(queue), amount);

        // Create order
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            paymentToken: address(_token),
            amount: amount,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Add to queue and verify
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));
        assertEq(queue.getQueueSize(address(this)), 1, "Queue size should be 1");
        
        // Verify order details
        IPP_Queue_v1.QueuedOrder memory queuedOrder = queue.getOrder(orderId);
        assertEq(queuedOrder.order_.recipient, recipient, "Wrong recipient");
        assertEq(queuedOrder.order_.amount, amount, "Wrong amount");
        
        // Remove and verify
        queue.exposed_removeFromQueue(orderId);
        assertEq(queue.getQueueSize(address(this)), 0, "Queue should be empty");
    }
}