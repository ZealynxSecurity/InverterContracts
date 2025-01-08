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
        assertTrue(queue.exposed_validPaymentReceiver(makeAddr("valid")));

        assertFalse(queue.exposed_validPaymentReceiver(address(0)));

        assertFalse(queue.exposed_validPaymentReceiver(address(queue)));
    }

    function test_validTotalAmount() public {
        assertTrue(queue.exposed_validTotalAmount(100));

        assertFalse(queue.exposed_validTotalAmount(0));
    }

    function test_validTokenBalance() public {
        address user = makeAddr("user");

        deal(address(_token), user, 1000);
        vm.startPrank(user);
        _token.approve(address(queue), 1000);
        vm.stopPrank();

        assertTrue(queue.exposed_validTokenBalance(address(_token), user, 500));

        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user, 2000)
        );
    }

    function testFuzz_validTokenBalance(
        uint256 amount,
        address user
    ) public {
        // Assume valid user address
        vm.assume(user != address(0));
        vm.assume(user != address(queue));
        vm.assume(user != address(this));
        
        // Bound amount to reasonable values
        amount = bound(amount, 1, 1e30);

        // Configurar token y balances
        deal(address(_token), user, amount);
        vm.startPrank(user);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Test con balance suficiente (amount/2 para asegurar que hay suficiente)
        assertTrue(
            queue.exposed_validTokenBalance(address(_token), user, amount/2),
            "Should have sufficient balance for half amount"
        );

        // Test con balance insuficiente (amount*2 para asegurar que es insuficiente)
        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user, amount*2),
            "Should not have sufficient balance for double amount"
        );

        // Log test parameters for debugging
        console.log("\nTest Parameters:");
        console.log("User:", user);
        console.log("Total Balance:", amount);
        console.log("Sufficient Test Amount:", amount/2);
        console.log("Insufficient Test Amount:", amount*2);
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

    function testFuzz_GetQueueSizeForClient(
        address client,
        uint8 numOrders
    ) public {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));
        
        // Bound number of orders to a reasonable range
        numOrders = uint8(bound(uint(numOrders), 1, 10));

        // Initial size should be 0
        assertEq(
            queue.getQueueSizeForClient(client),
            0,
            "Initial queue size should be 0"
        );

        // Create and store order IDs
        uint[] memory orderIds = new uint[](numOrders);
        
        // Add multiple orders
        for(uint8 i = 0; i < numOrders; i++) {
            IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: makeAddr(string.concat("recipient", vm.toString(i))),
                amount: 100,
                paymentToken: address(_token),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: bytes32(0),
                data: new bytes32[](0)
            });

            _token.mint(client, 100);
            vm.startPrank(client);
            _token.approve(address(queue), 100);
            vm.stopPrank();
            
            orderIds[i] = queue.exposed_addPaymentOrderToQueue(order, client);
        }

        // Verify queue size after adding orders
        assertEq(
            queue.getQueueSizeForClient(client),
            numOrders,
            "Queue size should match number of orders added"
        );

        // Cancel orders one by one and check size decrements
        for(uint8 i = 0; i < numOrders; i++) {
            queue.cancelPaymentOrderThroughQueueId(
                orderIds[i],
                IERC20PaymentClientBase_v1(client)
            );
            
            assertEq(
                queue.getQueueSizeForClient(client),
                numOrders - (i + 1),
                "Queue size should decrease after each cancellation"
            );
        }

        // Final size should be 0
        assertEq(
            queue.getQueueSizeForClient(client),
            0,
            "Final queue size should be 0"
        );

        // Test size for non-existent client
        assertEq(
            queue.getQueueSizeForClient(address(0)),
            0,
            "Queue size should be 0 for non-existent client"
        );

        // Log test parameters
        console.log("\nTest Parameters:");
        console.log("Client:", client);
        console.log("Number of Orders:", numOrders);
        console.log("Order IDs:");
        for(uint8 i = 0; i < numOrders; i++) {
            console.log("  Order", i, ":", orderIds[i]);
        }
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

    function testFuzz_GetOrder_GivenValidOrderId(
        address client,
        address recipient,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(recipient != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(queue));
        vm.assume(client != recipient);
        
        // Bound amount to reasonable values
        amount = uint96(bound(uint256(amount), 1, 1e30));
        
        // Bound chain IDs to reasonable values
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Create order with fuzzed parameters
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup tokens for the client
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Add the order
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);

        // Get the queued order
        IPP_Queue_v1.QueuedOrder memory queuedOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );

        // Verify all order details
        assertEq(
            queuedOrder.order_.recipient,
            recipient,
            "Order recipient should match"
        );
        assertEq(
            queuedOrder.order_.amount,
            amount,
            "Order amount should match"
        );
        assertEq(
            queuedOrder.order_.paymentToken,
            address(_token),
            "Order token should match"
        );
        assertEq(
            queuedOrder.order_.originChainId,
            originChainId,
            "Origin chain ID should match"
        );
        assertEq(
            queuedOrder.order_.targetChainId,
            targetChainId,
            "Target chain ID should match"
        );
        assertEq(
            uint(queuedOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Order should be in PROCESSING state"
        );
        assertEq(
            queuedOrder.orderId_,
            orderId,
            "Order ID should match"
        );
        assertEq(
            queuedOrder.client_,
            client,
            "Order client should match"
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

   function testFuzz_GetOrder_GivenCancelledOrder(
        address client,
        address recipient,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(recipient != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(queue));
        vm.assume(client != recipient);
        
        // Bound amount to reasonable values
        amount = uint96(bound(uint256(amount), 1, 1e30));
        
        // Bound chain IDs to reasonable values
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Create order with fuzzed parameters
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup tokens for the client
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Add the order
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);

        // Get initial state and verify it's PROCESSING
        IPP_Queue_v1.QueuedOrder memory initialOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );
        assertEq(
            uint(initialOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Initial state should be PROCESSING"
        );

        // Cancel the order
        queue.cancelPaymentOrderThroughQueueId(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );

        // Get the cancelled order
        IPP_Queue_v1.QueuedOrder memory cancelledOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );

        // Verify cancelled state
        assertEq(
            uint(cancelledOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.CANCELLED),
            "Order should be in CANCELLED state"
        );

        // Verify order details remain unchanged after cancellation
        assertEq(
            cancelledOrder.order_.recipient,
            recipient,
            "Recipient should remain unchanged after cancellation"
        );
        assertEq(
            cancelledOrder.order_.amount,
            amount,
            "Amount should remain unchanged after cancellation"
        );
        assertEq(
            cancelledOrder.order_.paymentToken,
            address(_token),
            "Token should remain unchanged after cancellation"
        );
        assertEq(
            cancelledOrder.order_.originChainId,
            originChainId,
            "Origin chain ID should remain unchanged after cancellation"
        );
        assertEq(
            cancelledOrder.order_.targetChainId,
            targetChainId,
            "Target chain ID should remain unchanged after cancellation"
        );
        assertEq(
            cancelledOrder.orderId_,
            orderId,
            "Order ID should remain unchanged after cancellation"
        );
        assertEq(
            cancelledOrder.client_,
            client,
            "Client should remain unchanged after cancellation"
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

    function testFuzz_GetOrder_GivenProcessedOrder(
        address client,
        address recipient,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(recipient != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(queue));
        vm.assume(client != recipient);
        
        // Bound amount to reasonable values
        amount = uint96(bound(uint256(amount), 1, 1e30));
        
        // Bound chain IDs to reasonable values
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Create order with fuzzed parameters
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup tokens for the client
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Add the order
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);

        // Get initial state and verify it's PROCESSING
        IPP_Queue_v1.QueuedOrder memory initialOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );
        assertEq(
            uint(initialOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Initial state should be PROCESSING"
        );

        // Process the order
        queue.exposed_updateOrderState(
            orderId,
            IPP_Queue_v1.RedemptionState.COMPLETED
        );
        queue.exposed_removeFromQueue(orderId);

        // Get the processed order
        IPP_Queue_v1.QueuedOrder memory processedOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );

        // Verify completed state
        assertEq(
            uint(processedOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.COMPLETED),
            "Order should be in COMPLETED state"
        );

        // Verify order details remain unchanged after processing
        assertEq(
            processedOrder.order_.recipient,
            recipient,
            "Recipient should remain unchanged after processing"
        );
        assertEq(
            processedOrder.order_.amount,
            amount,
            "Amount should remain unchanged after processing"
        );
        assertEq(
            processedOrder.order_.paymentToken,
            address(_token),
            "Token should remain unchanged after processing"
        );
        assertEq(
            processedOrder.order_.originChainId,
            originChainId,
            "Origin chain ID should remain unchanged after processing"
        );
        assertEq(
            processedOrder.order_.targetChainId,
            targetChainId,
            "Target chain ID should remain unchanged after processing"
        );
        assertEq(
            processedOrder.orderId_,
            orderId,
            "Order ID should remain unchanged after processing"
        );
        assertEq(
            processedOrder.client_,
            client,
            "Client should remain unchanged after processing"
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

    function testFuzz_RevertWhenAddingInvalidOrder(
        address client,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint256(amount), 1, 1e30));
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));

        // Create invalid orders and test each case
        IERC20PaymentClientBase_v1.PaymentOrder[] memory invalidOrders = new IERC20PaymentClientBase_v1.PaymentOrder[](3);

        // Case 0: Invalid token (address(0))
        invalidOrders[0] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: makeAddr("recipient"),
            amount: amount,
            paymentToken: address(0),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Case 1: Invalid recipient (address(0))
        invalidOrders[1] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0),
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Case 2: Invalid amount (0)
        invalidOrders[2] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: makeAddr("recipient"),
            amount: 0,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        string[3] memory testCases = [
            "Invalid token (address(0))",
            "Invalid recipient (address(0))",
            "Invalid amount (0)"
        ];

        // Test each invalid order
        for (uint i = 0; i < invalidOrders.length; i++) {
            // Only setup tokens if we're using a valid token
            if (invalidOrders[i].paymentToken != address(0)) {
                _token.mint(client, amount);
                vm.startPrank(client);
                _token.approve(address(queue), amount);
                vm.stopPrank();

                // For valid tokens, expect QueueOperationFailed error
                vm.expectRevert(
                    abi.encodeWithSignature(
                        "Module__PP_Queue_QueueOperationFailed(address)",
                        client
                    )
                );
            } else {
                // For invalid token (address(0)), expect a revert without data
                vm.expectRevert();
            }

            queue.exposed_addPaymentOrderToQueue(invalidOrders[i], client);
        }
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

   function testFuzz_GetQueueHead_GivenPartiallyProcessedQueue(
        address client,
        address recipient,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint256(amount), 1, 1e30));
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(0));

        // Authorize client
        _authorizer.setIsAuthorized(client, true);
        paymentClient.setIsAuthorized(client, true);

        // Create a valid order
        IERC20PaymentClientBase_v1.PaymentOrder memory order = 
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Add first order
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        uint orderId1 = queue.exposed_addPaymentOrderToQueue(order, client);
        vm.stopPrank();

        // Add second order
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        queue.exposed_addPaymentOrderToQueue(order, client);
        vm.stopPrank();

        // Cancel first order
        vm.prank(client);
        queue.cancelPaymentOrderThroughQueueId(
            orderId1,
            IERC20PaymentClientBase_v1(client)
        );

        // Verify queue head is 2 after cancelling first order
        assertEq(
            queue.getQueueHead(client),
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

    function testFuzz_GetQueueHead_GivenFullyProcessedQueue(
        address client,
        address recipient,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint256(amount), 1, 1e30));
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(0));

        // Authorize client
        _authorizer.setIsAuthorized(client, true);
        paymentClient.setIsAuthorized(client, true);

        // Create a valid order
        IERC20PaymentClientBase_v1.PaymentOrder memory order = 
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Add first order
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        uint orderId1 = queue.exposed_addPaymentOrderToQueue(order, client);
        vm.stopPrank();

        // Add second order
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        uint orderId2 = queue.exposed_addPaymentOrderToQueue(order, client);
        vm.stopPrank();

        // Cancel both orders
        vm.startPrank(client);
        queue.cancelPaymentOrderThroughQueueId(
            orderId1,
            IERC20PaymentClientBase_v1(client)
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId2,
            IERC20PaymentClientBase_v1(client)
        );
        vm.stopPrank();

        // Verify queue head is sentinel after all orders cancelled
        assertEq(
            queue.getQueueHead(client),
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
        paymentClient.setToken(ERC20Mock(address(_token)));
        
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

    function testFuzz_ProcessNextOrder_GivenEmptyQueue(
        address client,
        address recipient,
        uint96 amount,
        uint256 originChainId,
        uint256 targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint256(amount), 1, 1e30));
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(0));

        // Authorize client
        _authorizer.setIsAuthorized(client, true);
        paymentClient.setIsAuthorized(client, true);

        // Create a valid order to initialize the queue
        IERC20PaymentClientBase_v1.PaymentOrder memory order = 
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Initialize queue by adding and removing an order
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);
        vm.stopPrank();

        // Remove the order to make queue empty
        queue.exposed_removeFromQueue(orderId);

        // Process next order on empty queue
        vm.prank(client);
        bool success = queue.exposed_processNextOrder(client);

        // Assert processing empty queue returns false
        assertFalse(success, "Processing empty queue should return false");
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

    // NEW TEST
    // event UnclaimableAmountAdded(address sender, address token, address recipient, uint96 amount);
    function testPaymentFailureWithNonStandardToken() public {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount = 100;
        
        // Deploy mock token that returns false on transfer but doesn't revert
        NonStandardTokenMock mockToken = new NonStandardTokenMock();
        mockToken.setFailTransferTo(recipient);
        
        // Create payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(mockToken),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup balances and approvals
        mockToken.mint(address(this), amount);
        mockToken.approve(address(queue), amount);

        // Add order to queue
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Process the payment (should fail gracefully)
        vm.expectEmit(true, true, true, true);
        emit UnclaimableAmountAdded(
            address(this),
            address(mockToken),
            recipient,
            amount
        );

        queue.exposed_processNextOrder(address(this));

        // Verify state changes
        assertEq(
            queue.unclaimable(address(this), address(mockToken), recipient),
            amount,
            "Amount should be marked as unclaimable"
        );

        IPP_Queue_v1.QueuedOrder memory queuedOrder = 
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(address(this)));
        assertEq(
            uint(queuedOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.CANCELLED),
            "Order should be cancelled"
        );

        // Verify queue state
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            0,
            "Queue should be empty after failed processing"
        );
    }

    function testClaimPreviouslyUnclaimable() public {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount = 100;
        
        // Deploy mock token that returns false on transfer but doesn't revert
        NonStandardTokenMock mockToken = new NonStandardTokenMock();
        mockToken.setFailTransferTo(recipient); // Only fail transfers to recipient
        
        // Add payment order directly to payment client
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(mockToken),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        paymentClient.addPaymentOrderUnchecked(order);
        
        // Setup balances and approvals
        mockToken.mint(address(paymentClient), amount);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount);

        // Add order to queue and process it (will fail and create unclaimable amount)
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        vm.prank(address(paymentClient));
        queue.exposed_processNextOrder(address(paymentClient));

        // Verify initial unclaimable amount
        assertEq(
            queue.unclaimable(address(paymentClient), address(mockToken), recipient),
            amount,
            "Initial unclaimable amount incorrect"
        );

        // Test claiming with no balance (should fail)
        vm.expectRevert();
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);

        // Now allow transfers to recipient and try again
        mockToken.setFailTransferTo(address(0)); // Allow all transfers
        mockToken.mint(address(paymentClient), amount);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount);

        // Claim the unclaimable amount (should succeed now)
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);
        
        // Verify unclaimable amount is now 0
        assertEq(
            queue.unclaimable(address(paymentClient), address(mockToken), recipient),
            0,
            "Unclaimable amount should be 0 after claiming"
        );

        // Try to claim again (should fail)
        vm.expectRevert(abi.encodeWithSignature("Module__PaymentProcessor__NothingToClaim(address,address)", address(paymentClient), recipient));
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);
    }

    function testClaimPreviouslyUnclaimableMultipleAmounts() public {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount1 = 100;
        uint96 amount2 = 200;
        
        // Create and configure mock token that will fail transfers to recipient
        NonStandardTokenMock mockToken = new NonStandardTokenMock();
        mockToken.setFailTransferTo(recipient);
        paymentClient.setToken(ERC20Mock(address(mockToken)));
        
        // Add first payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order1 = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount1,
            paymentToken: address(mockToken),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Add second payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order2 = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount2,
            paymentToken: address(mockToken),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Process both orders (they will fail and create unclaimable amounts)
        paymentClient.addPaymentOrderUnchecked(order1);
        paymentClient.addPaymentOrderUnchecked(order2);
        
        // Setup balances and approvals for initial failed transfers
        mockToken.mint(address(paymentClient), amount1 + amount2);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount1 + amount2);

        // Add orders to queue and process them
        queue.exposed_addPaymentOrderToQueue(order1, address(paymentClient));
        queue.exposed_addPaymentOrderToQueue(order2, address(paymentClient));
        
        vm.prank(address(paymentClient));
        queue.exposed_processNextOrder(address(paymentClient));
        vm.prank(address(paymentClient));
        queue.exposed_processNextOrder(address(paymentClient));

        // Verify total unclaimable amount
        assertEq(
            queue.unclaimable(address(paymentClient), address(mockToken), recipient),
            amount1 + amount2,
            "Total unclaimable amount incorrect"
        );

        // Test claiming with no balance (should fail)
        vm.expectRevert();
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);

        // Test claiming while transfers are still failing (should fail)
        vm.prank(address(paymentClient));
        mockToken.mint(address(paymentClient), amount1 + amount2);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount1 + amount2);
        vm.expectRevert();
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);

        // Now allow transfers to recipient
        mockToken.setFailTransferTo(address(0)); // Allow all transfers
        mockToken.mint(address(paymentClient), amount1 + amount2);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount1 + amount2);
        
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);
        
        // Verify all amounts were claimed
        assertEq(
            queue.unclaimable(address(paymentClient), address(mockToken), recipient),
            0,
            "Unclaimable amount should be 0 after claiming"
        );

        // Try to claim again (should fail)
        vm.expectRevert(abi.encodeWithSignature("Module__PaymentProcessor__NothingToClaim(address,address)", address(paymentClient), recipient));
        queue.claimPreviouslyUnclaimable(address(paymentClient), address(mockToken), recipient);
    }
    // @audit
    event PaymentQueueExecuted(
        address sender,
        address recipient,
        uint256 amount
    );
    function testExecutePaymentQueueWithMultipleOrders() public {
        // Setup
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");
        uint96 amount1 = 100;
        uint96 amount2 = 200;
        
        // Create orders
        IERC20PaymentClientBase_v1.PaymentOrder memory order1 = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient1,
            amount: amount1,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        IERC20PaymentClientBase_v1.PaymentOrder memory order2 = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient2,
            amount: amount2,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup payment client
        paymentClient.setIsAuthorized(address(queue), true);
        paymentClient.setToken(ERC20Mock(address(_token)));
        
        // Add orders to payment client
        paymentClient.addPaymentOrderUnchecked(order1);
        paymentClient.addPaymentOrderUnchecked(order2);

        // Setup balances and approvals
        _token.mint(address(paymentClient), amount1 + amount2);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount1 + amount2);

        // Add orders to queue
        queue.exposed_addPaymentOrderToQueue(order1, address(paymentClient));
        queue.exposed_addPaymentOrderToQueue(order2, address(paymentClient));

        // Verify initial queue size
        assertEq(queue.getQueueSizeForClient(address(paymentClient)), 2, "Queue should have 2 orders");

        // Execute queue
        vm.prank(address(paymentClient));
        queue.exposed_executePaymentQueue(address(paymentClient));

        // Verify final state
        assertEq(queue.getQueueSizeForClient(address(paymentClient)), 0, "Queue should be empty");
        assertEq(_token.balanceOf(recipient1), amount1, "Recipient1 should have received tokens");
        assertEq(_token.balanceOf(recipient2), amount2, "Recipient2 should have received tokens");
    }
    // ok
    function testOrderExistsWithDifferentStates() public {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount = 100;
        
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Test non-existent order
        assertFalse(
            queue.exposed_orderExists(1, IERC20PaymentClientBase_v1(address(paymentClient))),
            "Non-existent order should return false"
        );

        // Setup payment client
        paymentClient.setToken(ERC20Mock(address(_token)));
        paymentClient.addPaymentOrderUnchecked(order);

        // Setup balances and approvals
        _token.mint(address(paymentClient), amount);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add order and test
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        assertTrue(
            queue.exposed_orderExists(orderId, IERC20PaymentClientBase_v1(address(paymentClient))),
            "Existing order should return true"
        );

        // Update to CANCELLED state and test
        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState.CANCELLED);
        assertTrue(
            queue.exposed_orderExists(orderId, IERC20PaymentClientBase_v1(address(paymentClient))),
            "Cancelled order should still exist"
        );

        // Add another order and test
        uint orderId2 = queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        assertTrue(
            queue.exposed_orderExists(orderId2, IERC20PaymentClientBase_v1(address(paymentClient))),
            "Second order should exist"
        );

        // Complete second order and test
        vm.prank(address(paymentClient));
        queue.exposed_executePaymentQueue(address(paymentClient));
        assertTrue(
            queue.exposed_orderExists(orderId2, IERC20PaymentClientBase_v1(address(paymentClient))),
            "Completed order should still exist"
        );
    }

    function testCancelCompletedOrder() public {
        // Create a new order
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Process the order by transferring tokens directly
        vm.startPrank(address(this));
        _token.transfer(order.recipient, order.amount);
        vm.stopPrank();

        // Update order state to COMPLETED
        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState.COMPLETED);

        // Try to cancel a completed order
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidState()"
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId,
            IERC20PaymentClientBase_v1(address(this))
        );
    }

    function testCancelNonExistentOrder() public {
        uint nonExistentOrderId = 999;

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                nonExistentOrderId
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            nonExistentOrderId,
            IERC20PaymentClientBase_v1(address(this))
        );
    }

    //ok
    function testCancelAlreadyCancelledOrder() public {
        // Añadir una orden
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Cancelar la orden
        queue.cancelPaymentOrderThroughQueueId(
            orderId,
            IERC20PaymentClientBase_v1(address(this))
        );

        // Intentar cancelar la orden nuevamente
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidState()"
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId,
            IERC20PaymentClientBase_v1(address(this))
        );
    }

//ok
   function testFuzz_OrderExistsWithDifferentStates(
        address recipient,
        uint96 amount,
        uint8 originChainId,
        uint8 targetChainId
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(queue));
        vm.assume(recipient != address(paymentClient));
        vm.assume(recipient != address(_orchestrator));

        amount = uint96(bound(uint(amount), 1, type(uint96).max));
        originChainId = uint8(bound(uint(originChainId), block.chainid, block.chainid));
        targetChainId = uint8(bound(uint(targetChainId), block.chainid, block.chainid));
        
        console.log("Test with amount:", amount);
        console.log("Payment Client:", address(paymentClient));
        console.log("Queue:", address(queue));
        console.log("Recipient:", recipient);
        
        // Setup initial state
        paymentClient.setToken(ERC20Mock(address(_token)));
        _token.mint(address(paymentClient), amount);
        
        // First approve from payment client to queue
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount);
        console.log("\nInitial state:");
        console.log("Client balance:", _token.balanceOf(address(paymentClient)));
        console.log("Queue allowance from client:", _token.allowance(address(paymentClient), address(queue)));
        vm.stopPrank();

        // Create and process orders
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        paymentClient.addPaymentOrderUnchecked(order);

        // Add first order (will be cancelled)
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState.CANCELLED);

        // Add second order (will be processed)
        uint orderId2 = queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        
        // Log order state before setting to PROCESSING
        IPP_Queue_v1.QueuedOrder memory orderBefore = queue.getOrder(
            orderId2,
            IERC20PaymentClientBase_v1(address(paymentClient))
        );
        console.log("\nOrder state before:", uint(orderBefore.state_), "(PROCESSING)");
        
        // No need to set to PROCESSING, it's already in that state
        
        console.log("\nProcessing order...");
        // Process order and check result
        vm.startPrank(address(paymentClient));
        bool success = queue.exposed_processNextOrder(address(paymentClient));
        console.log("Process result:", success);
        
        // Check final state based on token balances
        console.log("\nFinal state:");
        uint256 recipientBalance = _token.balanceOf(recipient);
        uint256 clientBalance = _token.balanceOf(address(paymentClient));
        console.log("Recipient balance:", recipientBalance);
        console.log("Client balance:", clientBalance);

        // If the transfer was successful (recipient got tokens)
        if (recipientBalance == amount) {
            assertTrue(success, "Process next order failed");
            assertEq(clientBalance, 0, "Client balance should be 0");
            
            // Verify that the order is no longer in the queue
            uint[] memory queue_orders = queue.getOrderQueue(address(paymentClient));
            assertEq(queue_orders.length, 0, "Queue should be empty after successful transfer");
        } else {
            assertFalse(success, "Process next order should have failed");
            assertEq(clientBalance, amount, "Client should keep balance");
            
            // Try to identify why the transfer failed
            vm.startPrank(address(queue));
            try _token.transferFrom(address(paymentClient), recipient, amount) returns (bool result) {
                console.log("Manual transfer after failure succeeded:", result);
            } catch Error(string memory reason) {
                console.log("Manual transfer after failure failed with:", reason);
            }
            vm.stopPrank();
        }
        vm.stopPrank();
    }
    //ok
    function testProcessNextOrderFailure() public {
        // Setup a basic order
        address recipient = makeAddr("recipient");
        uint96 amount = 1000;
        
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Setup payment client and balances
        paymentClient.setToken(ERC20Mock(address(_token)));
        paymentClient.addPaymentOrderUnchecked(order);
        _token.mint(address(paymentClient), amount);
        
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add order to queue
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        
        // Get initial state
        IPP_Queue_v1.QueuedOrder memory initialState = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(address(paymentClient))
        );
        assertEq(uint(initialState.state_), uint(IPP_Queue_v1.RedemptionState.PROCESSING));

        // Try to process the order
        bool success = queue.exposed_processNextOrder(address(paymentClient));
        
        // Get final state
        IPP_Queue_v1.QueuedOrder memory finalState = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(address(paymentClient))
        );

        // Log all relevant information
        console.log("Success:", success);
        console.log("Initial State:", uint(initialState.state_), "(PROCESSING)");
        console.log("Final State:", uint(finalState.state_), 
            finalState.state_ == IPP_Queue_v1.RedemptionState.COMPLETED ? "(COMPLETED)" :
            finalState.state_ == IPP_Queue_v1.RedemptionState.CANCELLED ? "(CANCELLED)" :
            "(PROCESSING)");
        console.log("Recipient Balance:", _token.balanceOf(recipient));
        console.log("Client Balance:", _token.balanceOf(address(paymentClient)));
        console.log("Queue Allowance:", _token.allowance(address(paymentClient), address(queue)));
        
        // The order should either complete successfully or fail with a clear reason
        if (!success) {
            // If it failed, let's check why
            console.log("Has Sufficient Balance:", _token.balanceOf(address(paymentClient)) >= amount);
            console.log("Has Sufficient Allowance:", _token.allowance(address(paymentClient), address(queue)) >= amount);
        }
        
        vm.stopPrank();
    }

    function testInvalidStateTransition() public {
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState.CANCELLED);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId,
                uint(IPP_Queue_v1.RedemptionState.CANCELLED),
                uint(IPP_Queue_v1.RedemptionState.COMPLETED)
            )
        );
        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState.COMPLETED);

        IPP_Queue_v1.QueuedOrder memory finalOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(address(this))
        );
        assertEq(
            uint(finalOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.CANCELLED),
            "Order should remain CANCELLED"
        );
    }

    function testFuzz_InvalidStateTransition(
        address recipient,
        uint96 amount,
        uint8 fromState,
        uint8 toState
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(queue));
        vm.assume(recipient != address(paymentClient));
        vm.assume(amount > 0 && amount <= type(uint96).max);
        
        // Limit states (0=COMPLETED, 1=CANCELLED, 2=PROCESSING)
        fromState = uint8(bound(fromState, 0, 2));
        toState = uint8(bound(toState, 0, 2));
        
        if (
            // PROCESSING => x
            fromState == uint(IPP_Queue_v1.RedemptionState.PROCESSING) ||
            fromState == toState
        ) {
            return;
        }

        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(address(this), amount);
        _token.approve(address(queue), amount);
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState(fromState));

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId,
                fromState,
                toState
            )
        );
        queue.exposed_updateOrderState(orderId, IPP_Queue_v1.RedemptionState(toState));

        IPP_Queue_v1.QueuedOrder memory finalOrder = queue.getOrder(
            orderId,
            IERC20PaymentClientBase_v1(address(this))
        );
        assertEq(
            uint(finalOrder.state_),
            fromState,
            "Order state should not change"
        );

        console.log("\nTest Parameters:");
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);
        console.log("From State:", fromState);
        console.log("To State:", toState);
        console.log("Order ID:", orderId);
        console.log("Final State:", uint(finalOrder.state_));
    }

    function testFuzz_validQueueId_GivenInvalidId(
        uint queueId,
        address client
    ) public {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));
        
        // Create a valid order to initialize the queue counter
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint validQueueId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Ensure queueId is different from the valid one and not zero
        vm.assume(queueId != validQueueId);
        vm.assume(queueId != 0);

        // Verify that the invalid queue ID is detected
        assertFalse(
            queue.exposed_validQueueId(queueId, client),
            "Queue ID should be invalid"
        );

        // Log test parameters for debugging
        console.log("\nTest Parameters:");
        console.log("Queue ID:", queueId);
        console.log("Client:", client);
        console.log("Valid Queue ID:", validQueueId);
    }


    function testFuzz_CancelNonExistentOrder(
        uint orderId,
        address client
    ) public {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));
        
        // Create a valid order to have a reference point
        IERC20PaymentClientBase_v1.PaymentOrder memory order = IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint existingOrderId = queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Ensure orderId is different from the existing one
        orderId = bound(orderId, 1, type(uint).max);
        vm.assume(orderId != existingOrderId);
        
        // Try to cancel a non-existent order
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                client,
                orderId
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId,
            IERC20PaymentClientBase_v1(client)
        );

        // Log test parameters for debugging
        console.log("\nTest Parameters:");
        console.log("Non-existent Order ID:", orderId);
        console.log("Client:", client);
        console.log("Existing Order ID:", existingOrderId);
    }

    function testFuzz_CancelOrderWithZeroId(
        address client
    ) public {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));
        
        // Try to cancel order with ID 0
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidState()"
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            0,
            IERC20PaymentClientBase_v1(client)
        );

        // Log test parameters
        console.log("\nTest Parameters:");
        console.log("Client:", client);
    }
}
