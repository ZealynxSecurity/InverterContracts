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
import {PP_Queue_v1Mock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import "forge-std/console.sol";

// Internal
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

contract PP_Queue_v1 is ModuleTest {
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

    function testQueueOperations(address recipient, uint96 amount) public {
        // Ensure valid inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(queue));
        vm.assume(recipient != address(_orchestrator));
        vm.assume(amount > 0 && amount < type(uint96).max);

        // Setup
        _authorizer.setIsAuthorized(address(queue), true);
        _token.mint(address(this), amount);
        _token.approve(address(queue), amount);

        // Create payment order without flags or data
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // First add the order to the payment client
        paymentClient.addPaymentOrderUnchecked(order);

        // Then mint tokens and approve
        _token.mint(address(paymentClient), amount);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add to queue and verify
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(this));
        assertTrue(orderId > 0, "Order ID should be greater than 0");
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            1,
            "Queue size should be 1"
        );

        // Verify order details
        IPP_Queue_v1.QueuedOrder memory queuedOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(address(this)));
        assertEq(queuedOrder.order_.recipient, recipient, "Wrong recipient");
        assertEq(queuedOrder.order_.amount, amount, "Wrong amount");
        assertEq(
            queuedOrder.order_.paymentToken, address(_token), "Wrong token"
        );
        assertEq(
            uint(queuedOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Wrong state"
        );
        assertEq(queuedOrder.orderId_, orderId, "Wrong orderId");
        assertEq(queuedOrder.client_, address(this), "Wrong client");
        assertTrue(queuedOrder.timestamp_ > 0, "Invalid timestamp");

        // // Remove from queue and verify
        // queue.exposed_removeFromQueue(orderId);
        // assertEq(queue.getQueueSizeForClient(address(this)), 0, "Queue should be empty");
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
        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user, 2000)
        );
    }

    function testFuzz_validTotalAmount(uint amount) public {
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

    function testFuzz_validTokenBalance(uint balance, uint amount) public {
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
        bool isValid =
            queue.exposed_validTokenBalance(address(_token), user, amount);

        if (balance >= amount) {
            assertTrue(isValid, "Sufficient balance marked as invalid");
        } else {
            assertFalse(isValid, "Insufficient balance marked as valid");
        }
    }

    function testFuzz_getPaymentQueueId(
        uint queueId,
        uint8 flagBits,
        uint8 dataLength
    ) public {
        // Bound the data length to reasonable values
        dataLength = uint8(bound(dataLength, 0, 10));

        // Create flags - we'll test both with and without the ORDER_ID bit
        bytes32 flags = bytes32(uint(flagBits));

        // Create data array with fuzzed length
        bytes32[] memory data = new bytes32[](dataLength);
        if (dataLength > 0) {
            data[0] = bytes32(queueId);
        }

        uint retrievedId = queue.exposed_getPaymentQueueId(flags, data);

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

    //--------------------------------------------------------------------------
    // Test: Queue Size Functions
    //@audit
    function testGetQueueSizeForClient() public {
        // Should be 0 initially
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            0,
            "Initial queue size should be 0"
        );

        // Add an order
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: makeAddr("recipient"),
            amount: 100,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), 100);
        _token.approve(address(queue), 100);
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Should be 1 after adding
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            1,
            "Queue size should be 1 after adding"
        );

        // Should be 0 after removing
        queue.cancelPaymentOrderThroughQueueId(
            orderId, IERC20PaymentClientBase_v1(address(this))
        );
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            0,
            "Queue size should be 0 after removing"
        );

        // Should be 0 for non-existent client
        assertEq(
            queue.getQueueSizeForClient(address(0)),
            0,
            "Queue size should be 0 for non-existent client"
        );
    }

    //--------------------------------------------------------------------------
    // Test: Order Management

    function testGetOrder_GivenValidOrderId() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Get the order
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ =
            queue.getOrder(orderId_, IERC20PaymentClientBase_v1(address(this)));

        // Verify order details
        assertEq(
            queuedOrder_.order_.recipient,
            recipient_,
            "Order recipient should match"
        );
        assertEq(
            queuedOrder_.order_.amount, amount_, "Order amount should match"
        );
        assertEq(
            queuedOrder_.order_.paymentToken,
            address(_token),
            "Order token should match"
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Order should be in PROCESSING state"
        );
        assertEq(queuedOrder_.orderId_, orderId_, "Order ID should match");
        assertEq(
            queuedOrder_.client_, address(this), "Order client should match"
        );
    }

    function testGetOrder_RevertGivenInvalidOrderId() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                1
            )
        );
        queue.getOrder(1, IERC20PaymentClientBase_v1(address(this)));
    }

    function testGetOrder_GivenCancelledOrder() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Cancel the order
        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v1(address(this))
        );

        // Get the order and verify it's cancelled
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ =
            queue.getOrder(orderId_, IERC20PaymentClientBase_v1(address(this)));

        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.CANCELLED),
            "Order should be in CANCELLED state"
        );
    }

    function testGetOrder_GivenProcessedOrder() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Process the order
        queue.exposed_updateOrderState(
            orderId_, IPP_Queue_v1.RedemptionState.COMPLETED
        );
        queue.exposed_removeFromQueue(orderId_);

        // Get the order and verify it's completed
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ =
            queue.getOrder(orderId_, IERC20PaymentClientBase_v1(address(this)));

        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.COMPLETED),
            "Order should be in COMPLETED state"
        );
    }

    function testGetOrderQueue_GivenEmptyQueue() public {
        // Get queue for non-existent client.
        uint[] memory emptyQueue_ = queue.getOrderQueue(address(this));
        assertEq(emptyQueue_.length, 0, "Empty queue should have length 0.");
    }

    function testGetOrderQueue_GivenSingleOrder(
        address recipient_,
        uint96 amount_
    ) public {
        // Filter invalid inputs.
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0);

        // Create and add order.
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Get queue and verify.
        uint[] memory queueArray_ = queue.getOrderQueue(address(this));
        assertEq(queueArray_.length, 1, "Queue should have length 1.");
        assertEq(queueArray_[0], orderId_, "Queue should contain the order ID.");
    }

    function testGetOrderQueue_GivenMultipleOrders(uint8 numOrders_) public {
        // Bound number of orders between 2 and 5 for reasonable test performance.
        numOrders_ = uint8(bound(numOrders_, 2, 5));

        uint[] memory orderIds_ = new uint[](numOrders_);

        // Add multiple orders.
        for (uint i_; i_ < numOrders_; i_++) {
            // Create unique recipient and amount for each order.
            address recipient_ =
                makeAddr(string.concat("recipient", vm.toString(i_)));
            uint96 amount_ = uint96(i_ + 1) * 100;

            IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient_,
                amount: amount_,
                paymentToken: address(_token),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: bytes32(0),
                data: new bytes32[](0)
            });

            _token.mint(address(this), amount_);
            _token.approve(address(queue), amount_);
            orderIds_[i_] =
                queue.exposed_addPaymentOrderToQueue(order_, address(this));
        }

        // Get queue and verify.
        uint[] memory queueArray_ = queue.getOrderQueue(address(this));
        assertEq(
            queueArray_.length,
            numOrders_,
            "Queue length should match number of orders."
        );

        // Verify order IDs are in correct order (FIFO).
        for (uint i_; i_ < numOrders_; i_++) {
            assertEq(
                queueArray_[i_],
                orderIds_[i_],
                string.concat("Wrong order ID at position ", vm.toString(i_))
            );
        }
    }

    function testGetOrderQueue_GivenNonExistentClient() public {
        address nonExistentClient_ = makeAddr("nonExistentClient");
        uint[] memory queueArray_ = queue.getOrderQueue(nonExistentClient_);
        assertEq(
            queueArray_.length, 0, "Non-existent client queue should be empty."
        );
    }

    function testRevertWhenAddingInvalidOrder() public {
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0), // Invalid recipient
            amount: 100,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)", address(this)
            )
        );
        queue.exposed_addPaymentOrderToQueue(order, address(this));
    }

    function testRevertWhenCancellingNonExistentOrder() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                999
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            999, IERC20PaymentClientBase_v1(address(this))
        );
    }

    //--------------------------------------------------------------------------
    // Test: Fuzz Testing
    //@audit => NO
    function testFuzz_QueueOperations(address recipient, uint96 amount)
        public
    {
        // Ensure valid inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(queue));
        vm.assume(amount > 0 && amount < type(uint96).max);

        // Setup
        _authorizer.setIsAuthorized(address(queue), true);
        _token.mint(address(this), amount);
        _token.approve(address(queue), amount);

        // Create order
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            paymentToken: address(_token),
            amount: amount,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // First add the order to the payment client
        paymentClient.addPaymentOrderUnchecked(order);

        // Then mint tokens and approve
        _token.mint(address(paymentClient), amount);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add to queue and verify
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            1,
            "Queue size should be 1"
        );

        // Verify order details
        IPP_Queue_v1.QueuedOrder memory queuedOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(address(paymentClient)));
        assertEq(queuedOrder.order_.recipient, recipient, "Wrong recipient");
        assertEq(queuedOrder.order_.amount, amount, "Wrong amount");

        // Remove and verify
        queue.exposed_removeFromQueue(orderId);
        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            0,
            "Queue should be empty"
        );
    }

    function testGetQueueHead_GivenUninitializedQueue() public {
        vm.expectRevert(
            abi.encodeWithSignature("Library__LinkedIdList__InvalidPosition()")
        );
        queue.getQueueHead(address(this));
    }

    function testGetQueueHead_GivenSingleOrder() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueHead(address(this)),
            1,
            "Head should be 1 after adding first order"
        );
    }

    function testGetQueueHead_GivenMultipleOrders() public {
        // Add first order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Add second order
        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueHead(address(this)),
            1,
            "Head should be 1 after second order"
        );
    }

    function testGetQueueHead_GivenPartiallyProcessedQueue() public {
        // Add two orders
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId1_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Cancel first order
        queue.cancelPaymentOrderThroughQueueId(
            orderId1_, IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueHead(address(this)),
            2,
            "Head should be 2 after cancelling first order"
        );
    }

    function testGetQueueHead_GivenFullyProcessedQueue() public {
        // Add two orders
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId1_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId2_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Cancel both orders
        queue.cancelPaymentOrderThroughQueueId(
            orderId1_, IERC20PaymentClientBase_v1(address(this))
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId2_, IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueHead(address(this)),
            type(uint).max,
            "Head should be sentinel after all orders cancelled"
        );
    }

    function testGetQueueTail_GivenUninitializedQueue() public {
        assertEq(
            queue.getQueueTail(address(this)),
            0,
            "Tail should be 0 for uninitialized queue"
        );
    }

    function testGetQueueTail_GivenSingleOrder() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueTail(address(this)),
            1,
            "Tail should be 1 after first order"
        );
    }

    function testGetQueueTail_GivenMultipleOrders() public {
        // Add first order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Add second order
        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueTail(address(this)),
            2,
            "Tail should be 2 after second order"
        );
    }

    function testGetQueueTail_GivenPartiallyProcessedQueue() public {
        // Add two orders
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId1_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Cancel first order
        queue.cancelPaymentOrderThroughQueueId(
            orderId1_, IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueTail(address(this)),
            2,
            "Tail should remain 2 after cancelling first order"
        );
    }

    function testGetQueueTail_GivenFullyProcessedQueue() public {
        // Add two orders
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId1_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId2_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Cancel both orders
        queue.cancelPaymentOrderThroughQueueId(
            orderId1_, IERC20PaymentClientBase_v1(address(this))
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId2_, IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueTail(address(this)),
            type(uint).max,
            "Tail should be sentinel after all orders cancelled"
        );
    }

    /// @notice Tests that getQueueOperatorRole returns the correct role.
    function testGetQueueOperatorRole() public {
        assertEq(
            queue.getQueueOperatorRole(),
            keccak256("QUEUE_OPERATOR"),
            "Incorrect queue operator role"
        );
    }

    //--------------------------------------------------------------------------
    // Test: Process Next Order

    function test_processNextOrder_GivenValidOrder(
        address recipient_,
        uint96 amount_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0);

        // Add an order
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup payment client
        paymentClient.setIsAuthorized(address(queue), true);
        paymentClient.setToken(_token);

        // Add order to payment client first
        paymentClient.addPaymentOrderUnchecked(order_);

        _token.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        // Process next order as the payment client
        vm.prank(address(paymentClient));
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));
        assertTrue(success_, "Processing next order should succeed");

        // Verify token transfer
        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive tokens"
        );
    }

    function test_processNextOrder_GivenEmptyQueue() public {
        // Add an empty order to initialize the queue
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: makeAddr("recipient"),
            amount: 100,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Initialize queue by adding and removing an order
        _token.mint(address(paymentClient), 100);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), 100);
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(paymentClient)
        );
        queue.exposed_removeFromQueue(orderId_);

        // Process next order on empty queue
        vm.prank(address(paymentClient));
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));
        assertFalse(success_, "Processing empty queue should return false");
    }

    //--------------------------------------------------------------------------
    // Test: Execute Payment Transfer

    function test_executePaymentTransfer_GivenValidOrder(
        address recipient_,
        uint96 amount_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0);

        // Add an order
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // First add the order to the payment client
        paymentClient.addPaymentOrderUnchecked(order_);

        // Then mint tokens and approve
        _token.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        // Execute payment transfer
        bool success_ = queue.exposed_executePaymentTransfer(orderId_);
        assertTrue(success_, "Payment transfer should succeed");

        // Verify token transfer
        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive tokens"
        );
    }

    function test_executePaymentTransfer_RevertGivenInvalidOrder(
        uint orderId_
    ) public {
        // Ensure order ID is not 0
        vm.assume(orderId_ > 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)"
                    )
                ),
                orderId_,
                0,
                1
            )
        );
        queue.exposed_executePaymentTransfer(orderId_);
    }

    function test_executePaymentTransfer_RevertGivenInsufficientBalance(
        address recipient_,
        uint96 amount_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0);

        // Add an order
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "Module__PP_Queue_QueueOperationFailed(address)"
                    )
                ),
                address(this)
            )
        );
        queue.exposed_addPaymentOrderToQueue(order_, address(this));
    }

    //--------------------------------------------------------------------------
    // Test: Order Existence

    function test_orderExists_GivenValidOrder(
        address recipient_,
        uint96 amount_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0);

        // Add an order
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Verify order exists
        assertTrue(
            queue.exposed_orderExists(
                orderId_, IERC20PaymentClientBase_v1(address(this))
            ),
            "Order should exist"
        );
    }

    function test_orderExists_GivenInvalidOrder(uint orderId_) public {
        // Ensure order ID is not 0
        vm.assume(orderId_ > 0);

        // Test with non-existent order ID
        assertFalse(
            queue.exposed_orderExists(
                orderId_, IERC20PaymentClientBase_v1(address(this))
            ),
            "Non-existent order should not exist"
        );
    }

    function test_orderExists_GivenInvalidClient(
        address recipient_,
        uint96 amount_,
        address wrongClient_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0);
        vm.assume(wrongClient_ != address(0));
        vm.assume(wrongClient_ != address(this));

        // Add an order
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Test with wrong client
        assertFalse(
            queue.exposed_orderExists(
                orderId_,
                IERC20PaymentClientBase_v1(wrongClient_)
            ),
            "Order should not exist for wrong client"
        );
    }

    //--------------------------------------------------------------------------
    // Test: Internal Functions

    function test_validQueueId_GivenValidId() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Verify valid queue ID
        assertTrue(
            queue.exposed_validQueueId(orderId_, address(this)),
            "Queue ID should be valid"
        );
    }

    function test_validQueueId_GivenInvalidId() public {
        // Test with non-existent order ID
        assertFalse(
            queue.exposed_validQueueId(999, address(this)),
            "Non-existent queue ID should be invalid"
        );
    }

    function test_updateOrderState() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Update state to COMPLETED
        queue.exposed_updateOrderState(
            orderId_, IPP_Queue_v1.RedemptionState.COMPLETED
        );

        // Verify state update
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ =
            queue.getOrder(orderId_, IERC20PaymentClientBase_v1(address(this)));
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.COMPLETED),
            "Order state should be COMPLETED"
        );
    }

    function test_removeFromQueue() public {
        // Add an order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Verify initial queue size
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            1,
            "Initial queue size should be 1"
        );

        // Remove order from queue
        queue.exposed_removeFromQueue(orderId_);

        // Verify queue size after removal
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            0,
            "Queue should be empty after removal"
        );
    }
}
