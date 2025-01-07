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

import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

import {NonStandardTokenMock} from "test/utils/mocks/token/NonStandardTokenMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {PP_Queue_v1Mock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import "forge-std/console.sol";

// Internal
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

contract limpiotest is ModuleTest {
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
        vm.prank(admin);
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
        assertEq(address(queue.orchestrator()), address(_orchestrator));
    }

    function testSupportsInterface() public {
        assertTrue(
            queue.supportsInterface(type(IPaymentProcessor_v1).interfaceId)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        queue.init(_orchestrator, _METADATA, bytes(""));
    }


}