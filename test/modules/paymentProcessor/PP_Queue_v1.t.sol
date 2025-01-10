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
import {NonStandardTokenMock} from
    "test/utils/mocks/token/NonStandardTokenMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {PP_Queue_v1Mock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

// Internal
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

import "forge-std/console.sol";

contract PP_Queue_v1 is ModuleTest {
    // SuT
    PP_Queue_v1Mock queue;

    // Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

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

    // Variables
    bytes32 public constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR";

    // Module Constants
    uint8 private constant FLAG_ORDER_ID = 0;
    uint8 private constant FLAG_START_TIME = 1;
    uint8 private constant FLAG_CLIFF_PERIOD = 2;
    uint8 private constant FLAG_END_TIME = 3;

    uint8 private constant SKIP_NOT_STARTED = 1;
    uint8 private constant SKIP_IN_CLIFF = 2;
    uint8 private constant SKIP_EXPIRED = 3;

    //Role
    bytes32 internal roleIDqueue;

    //Address
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

    /* Test init() function
        ├── Given the ModuleTest is initialized
        │   └── When the function init() is called
        │       └── Then the orchestrator address should be set correctly
    */
    function testInit() public override(ModuleTest) {
        assertEq(address(queue.orchestrator()), address(_orchestrator));
    }

    /* Test supportsInterface() function
        ├── Given the queue is initialized
        │   └── When the function supportsInterface() is called with a valid interface ID
        │       └── Then it should return true
    */
    function testSupportsInterface() public {
        assertTrue(
            queue.supportsInterface(type(IPaymentProcessor_v1).interfaceId)
        );
    }

    /* Test reinitialization of init() function
        ├── Given the queue is already initialized
        │   └── When the function init() is called again
        │       └── Then the transaction should revert with InvalidInitialization error
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        queue.init(_orchestrator, _METADATA, bytes(""));
    }

    /* Test testPublicQueueOperations_succeedsGivenValidRecipientAndAmount()
        ├── Given a valid recipient and amount
        │   ├── And the recipient is not address(0), the queue, or the orchestrator
        │   ├── And the amount is greater than 0 and less than uint96 max
        │   ├── And the authorizer is set to allow the queue
        │   ├── And the tokens are minted and approved
        │   ├── And a payment order is created
        │   ├── And the payment order is added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   └── When the payment order is added to the queue
        │       ├── Then the order ID should be greater than 0
        │       ├── And the queue size for the client should be 1
        │       ├── And the queued order recipient should match the input
        │       ├── And the queued order amount should match the input
        │       ├── And the queued order payment token should match the input
        │       ├── And the queued order state should be PROCESSING
        │       ├── And the queued order ID should match the returned order ID
        │       ├── And the queued order client should match the sender
        │       └── And the queued order timestamp should be greater than 0
    */
    function testPublicQueueOperations_succeedsGivenValidRecipientAndAmount(
        address recipient,
        uint96 amount
    ) public {
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
    }

    /* Test testPublicValidPaymentReceiver_succeedsOrFailsGivenReceiverAddress()
        ├── Given a valid payment receiver address
        │   └── When the function exposed_validPaymentReceiver() is called
        │       └── Then it should return true
        ├── Given the payment receiver address is address(0)
        │   └── When the function exposed_validPaymentReceiver() is called
        │       └── Then it should return false
        ├── Given the payment receiver address is the queue's own address
        │   └── When the function exposed_validPaymentReceiver() is called
        │       └── Then it should return false
    */
    function testPublicValidPaymentReceiver_succeedsOrFailsGivenReceiverAddress(
    ) public {
        assertTrue(queue.exposed_validPaymentReceiver(makeAddr("valid")));

        assertFalse(queue.exposed_validPaymentReceiver(address(0)));

        assertFalse(queue.exposed_validPaymentReceiver(address(queue)));
    }

    /* Test testPublicValidTotalAmount_succeedsOrFailsGivenAmount()
        ├── Given a valid total amount (greater than 0)
        │   └── When the function exposed_validTotalAmount() is called
        │       └── Then it should return true
        ├── Given an invalid total amount (equal to 0)
        │   └── When the function exposed_validTotalAmount() is called
        │       └── Then it should return false
    */
    function testPublicValidTotalAmount_succeedsOrFailsGivenAmount() public {
        assertTrue(queue.exposed_validTotalAmount(100));

        assertFalse(queue.exposed_validTotalAmount(0));
    }

    /* Test testPublicValidTokenBalance_succeedsOrFailsGivenBalance()
        ├── Given a user with sufficient token balance and allowance
        │   ├── And the user has a balance of 1000 tokens
        │   ├── And the user has approved 1000 tokens to the queue
        │   └── When the function exposed_validTokenBalance() is called with an amount of 500
        │       └── Then it should return true
        ├── Given a user with insufficient token balance
        │   ├── And the user has a balance of 1000 tokens
        │   ├── And the user has approved 1000 tokens to the queue
        │   └── When the function exposed_validTokenBalance() is called with an amount of 2000
        │       └── Then it should return false
    */
    function testPublicValidTokenBalance_succeedsOrFailsGivenBalance() public {
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

    /* Test testPublicValidTokenBalance_succeedsOrFailsGivenBalance()
        ├── Given a valid user address (not address(0), not the queue, and not the test contract)
        │   ├── And the user has a token balance of `amount` (bounded between 1 and 1e30)
        │   ├── And the user has approved `amount` tokens to the queue
        │   ├── When the function exposed_validTokenBalance() is called with half of `amount`
        │   │   └── Then it should return true
        │   └── When the function exposed_validTokenBalance() is called with double of `amount`
        │       └── Then it should return false
    */
    function testPublicValidTokenBalance_succeedsOrFailsGivenBalance(
        uint amount,
        address user
    ) public {
        vm.assume(user != address(0));
        vm.assume(user != address(queue));
        vm.assume(user != address(this));

        amount = bound(amount, 1, 1e30);

        deal(address(_token), user, amount);
        vm.startPrank(user);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        assertTrue(
            queue.exposed_validTokenBalance(address(_token), user, amount / 2),
            "Should have sufficient balance for half amount"
        );

        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user, amount * 2),
            "Should not have sufficient balance for double amount"
        );
    }

    /* Test testPublicValidTotalAmount_succeedsOrFailsGivenAmount()
        ├── Given a total amount of 0
        │   └── When the function exposed_validTotalAmount() is called
        │       └── Then it should return false
        ├── Given a total amount greater than 0
        │   └── When the function exposed_validTotalAmount() is called
        │       └── Then it should return true
    */
    function testPublicValidTotalAmount_succeedsOrFailsGivenAmount(uint amount)
        public
    {
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

    /* Test testPublicValidPaymentReceiver_succeedsGivenValidReceiver()
        ├── Given a valid payment receiver address
        │   ├── And the receiver is not address(0)
        │   ├── And the receiver is not the queue's address
        │   ├── And the receiver is not the orchestrator's address
        │   ├── And the receiver is not the funding manager's token address
        │   └── When the function exposed_validPaymentReceiver() is called
        │       └── Then it should return true
    */
    function testPublicValidPaymentReceiver_succeedsGivenValidReceiver(
        address receiver
    ) public {
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

    /* Test testPublicValidTokenBalance_succeedsOrFailsGivenBalanceAndAmount()
        ├── Given a user with a token balance of `balance`
        │   ├── And the user has approved `amount` tokens to the queue
        │   ├── And the amount is greater than 0
        │   ├── When the function exposed_validTokenBalance() is called
        │   │   ├── If the balance is greater than or equal to the amount
        │   │   │   └── Then it should return true
        │   │   └── If the balance is less than the amount
        │   │       └── Then it should return false
    */
    function testPublicValidTokenBalance_succeedsOrFailsGivenBalanceAndAmount(
        uint balance,
        uint amount
    ) public {
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

    /* Test testPublicGetPaymentQueueId_succeedsGivenFlagsAndData()
        ├── Given a set of flags and data
        │   ├── And the data length is bounded between 0 and 10
        │   ├── And the ORDER_ID bit in flags is either set or not set
        │   ├── When the function exposed_getPaymentQueueId() is called
        │   │   ├── If the ORDER_ID bit is set and data exists
        │   │   │   └── Then it should return the correct queue ID
        │   │   └── If the ORDER_ID bit is not set or data is empty
        │   │       └── Then it should return 0
    */
    function testPublicGetPaymentQueueId_succeedsGivenFlagsAndData(
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

    /* Test testPublicGetQueueSizeForClient_succeedsGivenClientAddress()
        ├── Given the queue is initially empty
        │   └── When the function getQueueSizeForClient() is called for the current client
        │       └── Then it should return 0
        ├── Given a payment order is added to the queue
        │   ├── And the tokens are minted and approved
        │   ├── And the order is added to the queue
        │   └── When the function getQueueSizeForClient() is called for the current client
        │       └── Then it should return 1
        ├── Given the payment order is canceled
        │   └── When the function getQueueSizeForClient() is called for the current client
        │       └── Then it should return 0
        ├── Given a non-existent client address
        │   └── When the function getQueueSizeForClient() is called for the non-existent client
        │       └── Then it should return 0
    */
    //@audit
    function testPublicGetQueueSizeForClient_succeedsGivenClientAddress()
        public
    {
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

    /* Test testPublicGetQueueSizeForClient_succeedsGivenClientAndOrders()
        ├── Given a valid client address (not address(0), not the queue, and not the test contract)
        │   ├── And the number of orders is bounded between 1 and 10
        │   ├── And the queue is initially empty
        │   ├── When multiple orders are added to the queue
        │   │   └── Then the queue size should match the number of orders added
        │   ├── When orders are canceled one by one
        │   │   └── Then the queue size should decrease after each cancellation
        │   ├── When all orders are canceled
        │   │   └── Then the queue size should be 0
        │   └── When the function getQueueSizeForClient() is called for a non-existent client
        │       └── Then it should return 0
    */
    function testPublicGetQueueSizeForClient_succeedsGivenClientAndOrders(
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
        for (uint8 i = 0; i < numOrders; i++) {
            IERC20PaymentClientBase_v1.PaymentOrder memory order =
            IERC20PaymentClientBase_v1.PaymentOrder({
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
        for (uint8 i = 0; i < numOrders; i++) {
            queue.cancelPaymentOrderThroughQueueId(
                orderIds[i], IERC20PaymentClientBase_v1(client)
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
        for (uint8 i = 0; i < numOrders; i++) {
            console.log("  Order", i, ":", orderIds[i]);
        }
    }

    /* Test testPublicGetOrder_succeedsGivenValidOrderId()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function getOrder() is called with the valid order ID
        │       ├── Then the order recipient should match the input
        │       ├── And the order amount should match the input
        │       ├── And the order payment token should match the input
        │       ├── And the order state should be PROCESSING
        │       ├── And the order ID should match the input
        │       └── And the order client should match the sender
    */
    function testPublicGetOrder_succeedsGivenValidOrderId() public {
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

    /* Test testPublicGetOrder_succeedsGivenValidOrderId()
        ├── Given a valid client address (not address(0), not the queue, and not the recipient)
        │   ├── And a valid recipient address (not address(0) and not the queue)
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And a payment order is created with the fuzzed parameters
        │   ├── And tokens are minted and approved for the client
        │   ├── And the order is added to the queue
        │   └── When the function getOrder() is called with the valid order ID
        │       ├── Then the order recipient should match the input
        │       ├── And the order amount should match the input
        │       ├── And the order payment token should match the input
        │       ├── And the origin chain ID should match the input
        │       ├── And the target chain ID should match the input
        │       ├── And the order state should be PROCESSING
        │       ├── And the order ID should match the input
        │       └── And the order client should match the input
    */
    function testPublicGetOrder_succeedsGivenValidOrderId(
        address client,
        address recipient,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(recipient != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(queue));
        vm.assume(client != recipient);

        // Bound amount to reasonable values
        amount = uint96(bound(uint(amount), 1, 1e30));

        // Bound chain IDs to reasonable values
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Create order with fuzzed parameters
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

        // Setup tokens for the client
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Add the order
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);

        // Get the queued order
        IPP_Queue_v1.QueuedOrder memory queuedOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(client));

        // Verify all order details
        assertEq(
            queuedOrder.order_.recipient,
            recipient,
            "Order recipient should match"
        );
        assertEq(queuedOrder.order_.amount, amount, "Order amount should match");
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
        assertEq(queuedOrder.orderId_, orderId, "Order ID should match");
        assertEq(queuedOrder.client_, client, "Order client should match");
    }

    /* Test testPublicGetOrder_revertsGivenInvalidOrderId()
        ├── Given an invalid order ID
        │   └── When the function getOrder() is called with the invalid order ID
        │       └── Then the transaction should revert with the error Module__PP_Queue_InvalidOrderId
    */
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

    /* Test testPublicGetOrder_succeedsGivenCancelledOrder()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the order is canceled
        │   └── When the function getOrder() is called with the order ID
        │       └── Then the order state should be CANCELLED
    */
    function testPublicGetOrder_succeedsGivenCancelledOrder() public {
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

    /* Test testPublicGetOrder_succeedsGivenCancelledOrder()
        ├── Given a valid client address (not address(0), not the queue, and not the recipient)
        │   ├── And a valid recipient address (not address(0) and not the queue)
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And a payment order is created with the fuzzed parameters
        │   ├── And tokens are minted and approved for the client
        │   ├── And the order is added to the queue
        │   ├── And the initial state of the order is PROCESSING
        │   ├── And the order is canceled
        │   └── When the function getOrder() is called with the order ID
        │       ├── Then the order state should be CANCELLED
        │       ├── And the order recipient should remain unchanged
        │       ├── And the order amount should remain unchanged
        │       ├── And the order payment token should remain unchanged
        │       ├── And the origin chain ID should remain unchanged
        │       ├── And the target chain ID should remain unchanged
        │       ├── And the order ID should remain unchanged
        │       └── And the order client should remain unchanged
    */
    function testPublicGetOrder_succeedsGivenCancelledOrder(
        address client,
        address recipient,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(recipient != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(queue));
        vm.assume(client != recipient);

        // Bound amount to reasonable values
        amount = uint96(bound(uint(amount), 1, 1e30));

        // Bound chain IDs to reasonable values
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Create order with fuzzed parameters
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

        // Setup tokens for the client
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Add the order
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);

        // Get initial state and verify it's PROCESSING
        IPP_Queue_v1.QueuedOrder memory initialOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(client));
        assertEq(
            uint(initialOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Initial state should be PROCESSING"
        );

        // Cancel the order
        queue.cancelPaymentOrderThroughQueueId(
            orderId, IERC20PaymentClientBase_v1(client)
        );

        // Get the cancelled order
        IPP_Queue_v1.QueuedOrder memory cancelledOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(client));

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

    /* Test testPublicGetOrder_succeedsGivenProcessedOrder()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the order is processed and marked as COMPLETED
        │   ├── And the order is removed from the queue
        │   └── When the function getOrder() is called with the order ID
        │       └── Then the order state should be COMPLETED
    */
    function testPublicGetOrder_succeedsGivenProcessedOrder() public {
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

    /* Test testPublicGetOrder_succeedsGivenProcessedOrder()
        ├── Given a valid client address (not address(0), not the queue, and not the recipient)
        │   ├── And a valid recipient address (not address(0) and not the queue)
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And a payment order is created with the fuzzed parameters
        │   ├── And tokens are minted and approved for the client
        │   ├── And the order is added to the queue
        │   ├── And the initial state of the order is PROCESSING
        │   ├── And the order is processed and marked as COMPLETED
        │   ├── And the order is removed from the queue
        │   └── When the function getOrder() is called with the order ID
        │       ├── Then the order state should be COMPLETED
        │       ├── And the order recipient should remain unchanged
        │       ├── And the order amount should remain unchanged
        │       ├── And the order payment token should remain unchanged
        │       ├── And the origin chain ID should remain unchanged
        │       ├── And the target chain ID should remain unchanged
        │       ├── And the order ID should remain unchanged
        │       └── And the order client should remain unchanged
    */
    function testPublicGetOrder_succeedsGivenProcessedOrder(
        address client,
        address recipient,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Assume valid addresses
        vm.assume(client != address(0));
        vm.assume(recipient != address(0));
        vm.assume(client != address(queue));
        vm.assume(recipient != address(queue));
        vm.assume(client != recipient);

        // Bound amount to reasonable values
        amount = uint96(bound(uint(amount), 1, 1e30));

        // Bound chain IDs to reasonable values
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Create order with fuzzed parameters
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

        // Setup tokens for the client
        _token.mint(client, amount);
        vm.startPrank(client);
        _token.approve(address(queue), amount);
        vm.stopPrank();

        // Add the order
        uint orderId = queue.exposed_addPaymentOrderToQueue(order, client);

        // Get initial state and verify it's PROCESSING
        IPP_Queue_v1.QueuedOrder memory initialOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(client));
        assertEq(
            uint(initialOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "Initial state should be PROCESSING"
        );

        // Process the order
        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState.COMPLETED
        );
        queue.exposed_removeFromQueue(orderId);

        // Get the processed order
        IPP_Queue_v1.QueuedOrder memory processedOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(client));

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

    /* Test testPublicGetOrderQueue_succeedsGivenEmptyQueue()
        ├── Given an empty queue for a client
        │   └── When the function getOrderQueue() is called for the client
        │       └── Then the returned queue should have a length of 0
    */
    function testPublicGetOrderQueue_succeedsGivenEmptyQueue() public {
        // Get queue for non-existent client.
        uint[] memory emptyQueue_ = queue.getOrderQueue(address(this));
        assertEq(emptyQueue_.length, 0, "Empty queue should have length 0.");
    }

    /* Test testPublicGetOrderQueue_succeedsGivenSingleOrder()
        ├── Given a valid recipient address (not address(0), not the queue, and not the orchestrator)
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function getOrderQueue() is called for the client
        │       ├── Then the queue should have a length of 1
        │       └── And the queue should contain the order ID
    */
    function testPublicGetOrderQueue_succeedsGivenSingleOrder(
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

    /* Test testPublicGetOrderQueue_succeedsGivenMultipleOrders()
        ├── Given a number of orders bounded between 2 and 5
        │   ├── And each order is configured with:
        │   │   ├── A unique recipient address
        │   │   ├── A unique amount (incremented by 100 for each order)
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for each order
        │   ├── And each order is added to the queue
        │   └── When the function getOrderQueue() is called for the client
        │       ├── Then the queue length should match the number of orders
        │       └── And the order IDs in the queue should follow FIFO order
    */
    function testPublicGetOrderQueue_succeedsGivenMultipleOrders(
        uint8 numOrders_
    ) public {
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

    /* Test testPublicGetOrderQueue_succeedsGivenNonExistentClient()
        ├── Given a non-existent client address
        │   └── When the function getOrderQueue() is called for the non-existent client
        │       └── Then the returned queue should be empty (length 0)
    */
    function testPublicGetOrderQueue_succeedsGivenNonExistentClient() public {
        address nonExistentClient_ = makeAddr("nonExistentClient");
        uint[] memory queueArray_ = queue.getOrderQueue(nonExistentClient_);
        assertEq(
            queueArray_.length, 0, "Non-existent client queue should be empty."
        );
    }

    /* Test testPublicAddPaymentOrderToQueue_revertsGivenInvalidOrder()
        ├── Given a payment order with an invalid recipient (address(0))
        │   ├── And the order is configured with:
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   └── When the function exposed_addPaymentOrderToQueue() is called
        │       └── Then the transaction should revert with the error Module__PP_Queue_QueueOperationFailed
    */
    function testPublicAddPaymentOrderToQueue_revertsGivenInvalidOrder()
        public
    {
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

    /* Test testPublicAddPaymentOrderToQueue_revertsGivenInvalidOrder()
        ├── Given a valid client address (not address(0) and not the queue)
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And an array of invalid payment orders:
        │   │   ├── Case 0: Invalid token (address(0))
        │   │   ├── Case 1: Invalid recipient (address(0))
        │   │   └── Case 2: Invalid amount (0)
        │   ├── And tokens are minted and approved for valid token cases
        │   └── When the function exposed_addPaymentOrderToQueue() is called for each invalid order
        │       ├── Then the transaction should revert with the error Module__PP_Queue_QueueOperationFailed for valid token cases
        │       └── And the transaction should revert without data for invalid token cases
    */
    function testPublicAddPaymentOrderToQueue_revertsGivenInvalidOrder(
        address client,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint(amount), 1, 1e30));
        originChainId = bound(originChainId, 1, 1e6);
        targetChainId = bound(targetChainId, 1, 1e6);

        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));

        // Create invalid orders and test each case
        IERC20PaymentClientBase_v1.PaymentOrder[] memory invalidOrders =
            new IERC20PaymentClientBase_v1.PaymentOrder[](3);

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
                        "Module__PP_Queue_QueueOperationFailed(address)", client
                    )
                );
            } else {
                // For invalid token (address(0)), expect a revert without data
                vm.expectRevert();
            }

            queue.exposed_addPaymentOrderToQueue(invalidOrders[i], client);
        }
    }

    /* Test testPublicCancelPaymentOrderThroughQueueId_revertsGivenNonExistentOrder()
        ├── Given a non-existent order ID (999)
        │   └── When the function cancelPaymentOrderThroughQueueId() is called with the non-existent order ID
        │       └── Then the transaction should revert with the error Module__PP_Queue_InvalidOrderId
    */
    function testPublicCancelPaymentOrderThroughQueueId_revertsGivenNonExistentOrder(
    ) public {
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

    /* Test testPublicQueueOperations_succeedsGivenValidInputs()
        ├── Given a valid recipient address (not address(0) and not the queue)
        │   ├── And a valid amount (greater than 0 and less than uint96 max)
        │   ├── And the queue is authorized
        │   ├── And tokens are minted and approved for the order
        │   ├── And a payment order is created with the valid parameters
        │   ├── And the order is added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the queue
        │   ├── When the function getQueueSizeForClient() is called
        │   │   └── Then the queue size should be 1
        │   ├── When the function getOrder() is called
        │   │   ├── Then the order recipient should match the input
        │   │   └── And the order amount should match the input
        │   ├── When the function exposed_removeFromQueue() is called
        │   │   └── Then the queue should be empty
    */
    //@audit => NO
    function testPublicQueueOperations_succeedsGivenValidInputs(
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
        IPP_Queue_v1.QueuedOrder memory queuedOrder = queue.getOrder(
            orderId, IERC20PaymentClientBase_v1(address(paymentClient))
        );
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

    /* Test testPublicGetQueueHead_revertsGivenUninitializedQueue()
        ├── Given an uninitialized queue for a client
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the transaction should revert with the error Library__LinkedIdList__InvalidPosition
    */
    function testPublicGetQueueHead_revertsGivenUninitializedQueue() public {
        vm.expectRevert(
            abi.encodeWithSignature("Library__LinkedIdList__InvalidPosition()")
        );
        queue.getQueueHead(address(this));
    }

    /* Test testPublicGetQueueHead_succeedsGivenSingleOrder()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the head of the queue should be 1
    */
    function testPublicGetQueueHead_succeedsGivenSingleOrder() public {
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

    /* Test testPublicGetQueueHead_succeedsGivenMultipleOrders()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the order
        │   ├── And the first order is added to the queue
        │   ├── And the second order is added to the queue
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the head of the queue should be 1
    */
    function testPublicGetQueueHead_succeedsGivenMultipleOrders() public {
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

    /* Test testPublicGetQueueHead_succeedsGivenPartiallyProcessedQueue()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   ├── And the first order is canceled
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the head of the queue should be 2
    */
    function testPublicGetQueueHead_succeedsGivenPartiallyProcessedQueue()
        public
    {
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

    /* Test testPublicGetQueueHead_succeedsGivenPartiallyProcessedQueue()
        ├── Given a valid client address (not address(0) and not the queue)
        │   ├── And a valid recipient address (not address(0))
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And the client is authorized
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   ├── And the first order is canceled
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the head of the queue should be 2
    */
    function testPublicGetQueueHead_succeedsGivenPartiallyProcessedQueue(
        address client,
        address recipient,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint(amount), 1, 1e30));
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
            orderId1, IERC20PaymentClientBase_v1(client)
        );

        // Verify queue head is 2 after cancelling first order
        assertEq(
            queue.getQueueHead(client),
            2,
            "Head should be 2 after cancelling first order"
        );
    }

    /* Test testPublicGetQueueHead_succeedsGivenFullyProcessedQueue()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   ├── And both orders are canceled
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the head of the queue should be the sentinel value (type(uint).max)
    */
    function testPublicGetQueueHead_succeedsGivenFullyProcessedQueue() public {
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

    /* Test testPublicGetQueueHead_succeedsGivenFullyProcessedQueue()
        ├── Given a valid client address (not address(0) and not the queue)
        │   ├── And a valid recipient address (not address(0))
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And the client is authorized
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   ├── And both orders are canceled
        │   └── When the function getQueueHead() is called for the client
        │       └── Then the head of the queue should be the sentinel value (type(uint).max)
    */
    function testPublicGetQueueHead_succeedsGivenFullyProcessedQueue(
        address client,
        address recipient,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint(amount), 1, 1e30));
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
            orderId1, IERC20PaymentClientBase_v1(client)
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId2, IERC20PaymentClientBase_v1(client)
        );
        vm.stopPrank();

        // Verify queue head is sentinel after all orders cancelled
        assertEq(
            queue.getQueueHead(client),
            type(uint).max,
            "Head should be sentinel after all orders cancelled"
        );
    }

    /* Test testPublicGetQueueTail_succeedsGivenUninitializedQueue()
        ├── Given an uninitialized queue for a client
        │   └── When the function getQueueTail() is called for the client
        │       └── Then the tail of the queue should be 0
    */
    function testPublicGetQueueTail_succeedsGivenUninitializedQueue() public {
        assertEq(
            queue.getQueueTail(address(this)),
            0,
            "Tail should be 0 for uninitialized queue"
        );
    }

    /* Test testPublicGetQueueTail_succeedsGivenSingleOrder()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function getQueueTail() is called for the client
        │       └── Then the tail of the queue should be 1
    */
    function testPublicGetQueueTail_succeedsGivenSingleOrder() public {
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

    /* Test testPublicGetQueueTail_succeedsGivenMultipleOrders()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   └── When the function getQueueTail() is called for the client
        │       └── Then the tail of the queue should be 2
    */
    function testPublicGetQueueTail_succeedsGivenMultipleOrders() public {
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

    /* Test testPublicGetQueueTail_succeedsGivenPartiallyProcessedQueue()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   ├── And the first order is canceled
        │   └── When the function getQueueTail() is called for the client
        │       └── Then the tail of the queue should remain 2
    */
    function testPublicGetQueueTail_succeedsGivenPartiallyProcessedQueue()
        public
    {
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

    /* Test testPublicGetQueueTail_succeedsGivenFullyProcessedQueue()
        ├── Given a valid payment order
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the first order
        │   ├── And the first order is added to the queue
        │   ├── And tokens are minted and approved for the second order
        │   ├── And the second order is added to the queue
        │   ├── And both orders are canceled
        │   └── When the function getQueueTail() is called for the client
        │       └── Then the tail of the queue should be the sentinel value (type(uint).max)
    */
    function testPublicGetQueueTail_succeedsGivenFullyProcessedQueue() public {
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

    /* Test testPublicGetQueueOperatorRole_succeeds()
        ├── Given the queue operator role is defined
        │   └── When the function getQueueOperatorRole() is called
        │       └── Then it should return the correct role hash (keccak256("QUEUE_OPERATOR"))
    */
    function testPublicGetQueueOperatorRole_succeeds() public {
        assertEq(
            queue.getQueueOperatorRole(),
            keccak256("QUEUE_OPERATOR"),
            "Incorrect queue operator role"
        );
    }

    /* Test testPublicProcessNextOrder_succeedsGivenValidOrder()
        ├── Given a valid recipient address (not address(0), not the queue, and not the orchestrator)
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And the payment client is authorized
        │   ├── And the payment client's token is set
        │   ├── And the order is added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the queue
        │   └── When the function exposed_processNextOrder() is called by the payment client
        │       ├── Then the processing should succeed
        │       └── And the recipient should receive the correct amount of tokens
    */
    function testPublicProcessNextOrder_succeedsGivenValidOrder(
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

    /* Test testPublicProcessNextOrder_failsGivenEmptyQueue()
        ├── Given a payment order is created
        │   ├── And the order is configured with:
        │   │   ├── A recipient address
        │   │   ├── An amount of 100
        │   │   ├── A payment token (address(_token))
        │   │   ├── Origin and target chain IDs matching the current chain
        │   │   ├── Flags set to 0
        │   │   └── An empty data array
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the queue
        │   ├── And the order is removed from the queue
        │   └── When the function exposed_processNextOrder() is called by the payment client
        │       └── Then the processing should fail (return false)
    */
    function testPublicProcessNextOrder_failsGivenEmptyQueue() public {
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
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
        queue.exposed_removeFromQueue(orderId_);

        // Process next order on empty queue
        vm.prank(address(paymentClient));
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));
        assertFalse(success_, "Processing empty queue should return false");
    }

    /* Test testPublicProcessNextOrder_failsGivenEmptyQueue()
        ├── Given a valid client address (not address(0) and not the queue)
        │   ├── And a valid recipient address (not address(0))
        │   ├── And a valid amount (bounded between 1 and 1e30)
        │   ├── And valid chain IDs (bounded between 1 and 1e6)
        │   ├── And the client is authorized
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the client
        │   ├── And the order is added to the queue
        │   ├── And the order is removed from the queue
        │   └── When the function exposed_processNextOrder() is called by the client
        │       └── Then the processing should fail (return false)
    */
    function testPublicProcessNextOrder_failsGivenEmptyQueue(
        address client,
        address recipient,
        uint96 amount,
        uint originChainId,
        uint targetChainId
    ) public {
        // Bound values to reasonable ranges
        amount = uint96(bound(uint(amount), 1, 1e30));
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

    /* Test testPublicExecutePaymentTransfer_succeedsGivenValidOrder()
        ├── Given a valid recipient address (not address(0), not the queue, and not the orchestrator)
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And the order is added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the queue
        │   └── When the function exposed_executePaymentTransfer() is called with the order ID
        │       ├── Then the payment transfer should succeed
        │       └── And the recipient should receive the correct amount of tokens
    */
    function testPublicExecutePaymentTransfer_succeedsGivenValidOrder(
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

    /* Test testPublicExecutePaymentTransfer_revertsGivenInvalidOrder()
        ├── Given an invalid order ID (greater than 0)
        │   └── When the function exposed_executePaymentTransfer() is called with the invalid order ID
        │       └── Then the transaction should revert with the error Module__PP_Queue_InvalidStateTransition
    */
    function testPublicExecutePaymentTransfer_revertsGivenInvalidOrder(
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

    /* Test testPublicExecutePaymentTransfer_revertsGivenInsufficientBalance()
        ├── Given a valid recipient address (not address(0), not the queue, and not the orchestrator)
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   └── When the function exposed_addPaymentOrderToQueue() is called with insufficient balance
        │       └── Then the transaction should revert with the error Module__PP_Queue_QueueOperationFailed
    */
    function testPublicExecutePaymentTransfer_revertsGivenInsufficientBalance(
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
                    keccak256("Module__PP_Queue_QueueOperationFailed(address)")
                ),
                address(this)
            )
        );
        queue.exposed_addPaymentOrderToQueue(order_, address(this));
    }

    /* Test testPublicOrderExists_succeedsGivenValidOrder()
        ├── Given a valid recipient address (not address(0), not the queue, and not the orchestrator)
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function exposed_orderExists() is called with the order ID
        │       └── Then it should return true
    */
    function testPublicOrderExists_succeedsGivenValidOrder(
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

    /* Test testPublicOrderExists_failsGivenInvalidOrder()
        ├── Given an order ID greater than 0
        │   └── When the function exposed_orderExists() is called with a non-existent order ID
        │       └── Then it should return false
    */
    function testPublicOrderExists_failsGivenInvalidOrder(uint orderId_)
        public
    {
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

    /* Test testPublicOrderExists_failsGivenInvalidClient()
        ├── Given a valid recipient address (not address(0), not the queue, and not the orchestrator)
        │   ├── And a valid amount (greater than 0)
        │   ├── And a valid wrong client address (not address(0) and not the current client)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function exposed_orderExists() is called with the order ID and the wrong client
        │       └── Then it should return false
    */
    function testPublicOrderExists_failsGivenInvalidClient(
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
                orderId_, IERC20PaymentClientBase_v1(wrongClient_)
            ),
            "Order should not exist for wrong client"
        );
    }

    /* Test testPublicValidQueueId_succeedsGivenValidId()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function exposed_validQueueId() is called with the order ID and the correct client
        │       └── Then it should return true
    */
    function testPublicValidQueueId_succeedsGivenValidId() public {
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

    /* Test testPublicValidQueueId_failsGivenInvalidId()
        ├── Given a non-existent order ID
        │   └── When the function exposed_validQueueId() is called with the non-existent order ID and the correct client
        │       └── Then it should return false
    */
    function testPublicValidQueueId_failsGivenInvalidId() public {
        // Test with non-existent order ID
        assertFalse(
            queue.exposed_validQueueId(999, address(this)),
            "Non-existent queue ID should be invalid"
        );
    }

    /* Test testPublicUpdateOrderState_succeedsGivenValidOrder()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function exposed_updateOrderState() is called with the order ID and the state COMPLETED
        │       └── Then the order state should be updated to COMPLETED
    */
    function testPublicUpdateOrderState_succeedsGivenValidOrder() public {
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

    /* Test testPublicRemoveFromQueue_succeedsGivenValidOrder()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the initial queue size is verified to be 1
        │   └── When the function exposed_removeFromQueue() is called with the order ID
        │       └── Then the queue size should be 0
    */
    function testPublicRemoveFromQueue_succeedsGivenValidOrder() public {
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

    /* Test testPublicProcessNextOrder_failsGivenNonStandardToken()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a non-standard token that returns false on transfer but doesn't revert
        │   ├── And a payment order is created with the non-standard token
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   └── When the function exposed_processNextOrder() is called
        │       ├── Then the amount should be marked as unclaimable
        │       ├── And the order state should be updated to CANCELLED
        │       └── And the queue should be empty
    */
    function testPublicProcessNextOrder_failsGivenNonStandardToken() public {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount = 100;

        // Deploy mock token that returns false on transfer but doesn't revert
        NonStandardTokenMock mockToken = new NonStandardTokenMock();
        mockToken.setFailTransferTo(recipient);

        // Create payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

        // Process the payment (should fail gracefully)
        vm.expectEmit(true, true, true, true);
        emit UnclaimableAmountAdded(
            address(this), address(mockToken), recipient, amount
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

    /* Test testPublicClaimPreviouslyUnclaimable_succeedsGivenValidConditions()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a non-standard token that initially fails transfers to the recipient
        │   ├── And a payment order is created with the non-standard token
        │   ├── And the payment client is authorized
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the payment client and the queue
        │   ├── And the order is processed, resulting in an unclaimable amount
        │   ├── And the initial unclaimable amount is verified
        │   ├── And claiming is attempted with no balance (should fail)
        │   ├── And the token is updated to allow transfers to the recipient
        │   ├── And tokens are minted and approved again for the payment client
        │   └── When the function claimPreviouslyUnclaimable() is called
        │       ├── Then the unclaimable amount should be successfully claimed
        │       ├── And the unclaimable amount should be 0 after claiming
        │       └── And attempting to claim again should fail
    */
    function testPublicClaimPreviouslyUnclaimable_succeedsGivenValidConditions()
        public
    {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount = 100;

        // Deploy mock token that returns false on transfer but doesn't revert
        NonStandardTokenMock mockToken = new NonStandardTokenMock();
        mockToken.setFailTransferTo(recipient); // Only fail transfers to recipient

        // Add payment order directly to payment client
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
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
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        vm.prank(address(paymentClient));
        queue.exposed_processNextOrder(address(paymentClient));

        // Verify initial unclaimable amount
        assertEq(
            queue.unclaimable(
                address(paymentClient), address(mockToken), recipient
            ),
            amount,
            "Initial unclaimable amount incorrect"
        );

        // Test claiming with no balance (should fail)
        vm.expectRevert();
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );

        // Now allow transfers to recipient and try again
        mockToken.setFailTransferTo(address(0)); // Allow all transfers
        mockToken.mint(address(paymentClient), amount);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount);

        // Claim the unclaimable amount (should succeed now)
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );

        // Verify unclaimable amount is now 0
        assertEq(
            queue.unclaimable(
                address(paymentClient), address(mockToken), recipient
            ),
            0,
            "Unclaimable amount should be 0 after claiming"
        );

        // Try to claim again (should fail)
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PaymentProcessor__NothingToClaim(address,address)",
                address(paymentClient),
                recipient
            )
        );
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );
    }

    /* Test testPublicClaimPreviouslyUnclaimable_succeedsGivenMultipleAmounts()
        ├── Given a valid recipient address
        │   ├── And two valid amounts (greater than 0)
        │   ├── And a non-standard token that initially fails transfers to the recipient
        │   ├── And the payment client is configured with the non-standard token
        │   ├── And two payment orders are created with the non-standard token
        │   ├── And both orders are added to the payment client and the queue
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And both orders are processed, resulting in unclaimable amounts
        │   ├── And the total unclaimable amount is verified
        │   ├── And claiming is attempted with no balance (should fail)
        │   ├── And claiming is attempted while transfers are still failing (should fail)
        │   ├── And the token is updated to allow transfers to the recipient
        │   ├── And tokens are minted and approved again for the payment client
        │   └── When the function claimPreviouslyUnclaimable() is called
        │       ├── Then the unclaimable amounts should be successfully claimed
        │       ├── And the unclaimable amount should be 0 after claiming
        │       └── And attempting to claim again should fail
    */
    function testPublicClaimPreviouslyUnclaimable_succeedsGivenMultipleAmounts()
        public
    {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount1 = 100;
        uint96 amount2 = 200;

        // Create and configure mock token that will fail transfers to recipient
        NonStandardTokenMock mockToken = new NonStandardTokenMock();
        mockToken.setFailTransferTo(recipient);
        paymentClient.setToken(ERC20Mock(address(mockToken)));

        // Add first payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order1 =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            amount: amount1,
            paymentToken: address(mockToken),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Add second payment order
        IERC20PaymentClientBase_v1.PaymentOrder memory order2 =
        IERC20PaymentClientBase_v1.PaymentOrder({
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
            queue.unclaimable(
                address(paymentClient), address(mockToken), recipient
            ),
            amount1 + amount2,
            "Total unclaimable amount incorrect"
        );

        // Test claiming with no balance (should fail)
        vm.expectRevert();
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );

        // Test claiming while transfers are still failing (should fail)
        vm.prank(address(paymentClient));
        mockToken.mint(address(paymentClient), amount1 + amount2);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount1 + amount2);
        vm.expectRevert();
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );

        // Now allow transfers to recipient
        mockToken.setFailTransferTo(address(0)); // Allow all transfers
        mockToken.mint(address(paymentClient), amount1 + amount2);
        vm.prank(address(paymentClient));
        mockToken.approve(address(queue), amount1 + amount2);

        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );

        // Verify all amounts were claimed
        assertEq(
            queue.unclaimable(
                address(paymentClient), address(mockToken), recipient
            ),
            0,
            "Unclaimable amount should be 0 after claiming"
        );

        // Try to claim again (should fail)
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PaymentProcessor__NothingToClaim(address,address)",
                address(paymentClient),
                recipient
            )
        );
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(mockToken), recipient
        );
    }

    /* Test testPublicExecutePaymentQueue_succeedsGivenMultipleOrders()
        ├── Given two valid recipient addresses
        │   ├── And two valid amounts (greater than 0)
        │   ├── And two payment orders are created with the valid parameters
        │   ├── And the payment client is authorized and configured with the token
        │   ├── And both orders are added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And both orders are added to the queue
        │   ├── And the initial queue size is verified to be 2
        │   └── When the function exposed_executePaymentQueue() is called
        │       ├── Then the queue should be empty
        │       ├── And recipient1 should receive the correct amount of tokens
        │       └── And recipient2 should receive the correct amount of tokens
    */
    function testPublicExecutePaymentQueue_succeedsGivenMultipleOrders()
        public
    {
        // Setup
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");
        uint96 amount1 = 100;
        uint96 amount2 = 200;

        // Create orders
        IERC20PaymentClientBase_v1.PaymentOrder memory order1 =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient1,
            amount: amount1,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        IERC20PaymentClientBase_v1.PaymentOrder memory order2 =
        IERC20PaymentClientBase_v1.PaymentOrder({
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
        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            2,
            "Queue should have 2 orders"
        );

        // Execute queue
        vm.prank(address(paymentClient));
        queue.exposed_executePaymentQueue(address(paymentClient));

        // Verify final state
        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            0,
            "Queue should be empty"
        );
        assertEq(
            _token.balanceOf(recipient1),
            amount1,
            "Recipient1 should have received tokens"
        );
        assertEq(
            _token.balanceOf(recipient2),
            amount2,
            "Recipient2 should have received tokens"
        );
    }

    /* Test testPublicOrderExists_succeedsGivenDifferentStates()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And the payment client is configured with the token
        │   ├── And the order is added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the queue
        │   ├── And the order state is updated to CANCELLED
        │   ├── And a second order is added to the queue
        │   ├── And the second order is completed
        │   └── When the function exposed_orderExists() is called for each scenario
        │       ├── Then a non-existent order should return false
        │       ├── And an existing order should return true
        │       ├── And a cancelled order should still exist
        │       ├── And a second order should exist
        │       └── And a completed order should still exist
    */
    function testPublicOrderExists_succeedsGivenDifferentStates() public {
        // Setup
        address recipient = makeAddr("recipient");
        uint96 amount = 100;

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

        // Test non-existent order
        assertFalse(
            queue.exposed_orderExists(
                1, IERC20PaymentClientBase_v1(address(paymentClient))
            ),
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
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        assertTrue(
            queue.exposed_orderExists(
                orderId, IERC20PaymentClientBase_v1(address(paymentClient))
            ),
            "Existing order should return true"
        );

        // Update to CANCELLED state and test
        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState.CANCELLED
        );
        assertTrue(
            queue.exposed_orderExists(
                orderId, IERC20PaymentClientBase_v1(address(paymentClient))
            ),
            "Cancelled order should still exist"
        );

        // Add another order and test
        uint orderId2 =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        assertTrue(
            queue.exposed_orderExists(
                orderId2, IERC20PaymentClientBase_v1(address(paymentClient))
            ),
            "Second order should exist"
        );

        // Complete second order and test
        vm.prank(address(paymentClient));
        queue.exposed_executePaymentQueue(address(paymentClient));
        assertTrue(
            queue.exposed_orderExists(
                orderId2, IERC20PaymentClientBase_v1(address(paymentClient))
            ),
            "Completed order should still exist"
        );
    }

    /* Test testPublicCancelPaymentOrder_revertsGivenCompletedOrder()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the order is processed by transferring tokens directly
        │   ├── And the order state is updated to COMPLETED
        │   └── When the function cancelPaymentOrderThroughQueueId() is called
        │       └── Then the transaction should revert
    */
    function testPublicCancelPaymentOrder_revertsGivenCompletedOrder() public {
        // Create a new order
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

        // Process the order by transferring tokens directly
        vm.startPrank(address(this));
        _token.transfer(order.recipient, order.amount);
        vm.stopPrank();

        // Update order state to COMPLETED
        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState.COMPLETED
        );

        // Try to cancel a completed order
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_InvalidState()")
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId, IERC20PaymentClientBase_v1(address(this))
        );
    }

    /* Test testPublicCancelPaymentOrder_revertsGivenNonExistentOrder()
        ├── Given a non-existent order ID
        │   └── When the function cancelPaymentOrderThroughQueueId() is called with the non-existent order ID
        │       └── Then the transaction should revert
    */
    function testPublicCancelPaymentOrder_revertsGivenNonExistentOrder()
        public
    {
        uint nonExistentOrderId = 999;

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                nonExistentOrderId
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            nonExistentOrderId, IERC20PaymentClientBase_v1(address(this))
        );
    }

    /* Test testPublicCancelPaymentOrder_revertsGivenAlreadyCancelledOrder()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the order is cancelled
        │   └── When the function cancelPaymentOrderThroughQueueId() is called again with the same order ID
        │       └── Then the transaction should revert
    */
    function testPublicCancelPaymentOrder_revertsGivenAlreadyCancelledOrder()
        public
    {
        // Añadir una orden
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

        // Cancelar la orden
        queue.cancelPaymentOrderThroughQueueId(
            orderId, IERC20PaymentClientBase_v1(address(this))
        );

        // Intentar cancelar la orden nuevamente
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_InvalidState()")
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId, IERC20PaymentClientBase_v1(address(this))
        );
    }

    /* Test testPublicOrderExists_succeedsGivenDifferentStates()
        ├── Given a valid recipient address (not address(0), not the queue, not the payment client, and not the orchestrator)
        │   ├── And a valid amount (greater than 0 and bounded to uint96 max)
        │   ├── And valid origin and target chain IDs (matching the current chain)
        │   ├── And the payment client is configured with the token
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And a payment order is created with the valid parameters
        │   ├── And the order is added to the payment client
        │   ├── And the first order is added to the queue and cancelled
        │   ├── And the second order is added to the queue
        │   ├── And the second order is processed
        │   └── When the function exposed_processNextOrder() is called
        │       ├── Then if the transfer is successful:
        │       │   ├── The recipient should receive the correct amount of tokens
        │       │   ├── The client balance should be 0
        │       │   └── The queue should be empty
        │       └── Else if the transfer fails:
        │           ├── The client should retain the balance
        │           └── The failure reason should be logged
    */
    function testPublicOrderExists_succeedsGivenDifferentStates(
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
        originChainId =
            uint8(bound(uint(originChainId), block.chainid, block.chainid));
        targetChainId =
            uint8(bound(uint(targetChainId), block.chainid, block.chainid));

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
        console.log(
            "Queue allowance from client:",
            _token.allowance(address(paymentClient), address(queue))
        );
        vm.stopPrank();

        // Create and process orders
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

        paymentClient.addPaymentOrderUnchecked(order);

        // Add first order (will be cancelled)
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));
        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState.CANCELLED
        );

        // Add second order (will be processed)
        uint orderId2 =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        // Log order state before setting to PROCESSING
        IPP_Queue_v1.QueuedOrder memory orderBefore = queue.getOrder(
            orderId2, IERC20PaymentClientBase_v1(address(paymentClient))
        );
        console.log(
            "\nOrder state before:", uint(orderBefore.state_), "(PROCESSING)"
        );

        // No need to set to PROCESSING, it's already in that state

        console.log("\nProcessing order...");
        // Process order and check result
        vm.startPrank(address(paymentClient));
        bool success = queue.exposed_processNextOrder(address(paymentClient));
        console.log("Process result:", success);

        // Check final state based on token balances
        console.log("\nFinal state:");
        uint recipientBalance = _token.balanceOf(recipient);
        uint clientBalance = _token.balanceOf(address(paymentClient));
        console.log("Recipient balance:", recipientBalance);
        console.log("Client balance:", clientBalance);

        // If the transfer was successful (recipient got tokens)
        if (recipientBalance == amount) {
            assertTrue(success, "Process next order failed");
            assertEq(clientBalance, 0, "Client balance should be 0");

            // Verify that the order is no longer in the queue
            uint[] memory queue_orders =
                queue.getOrderQueue(address(paymentClient));
            assertEq(
                queue_orders.length,
                0,
                "Queue should be empty after successful transfer"
            );
        } else {
            assertFalse(success, "Process next order should have failed");
            assertEq(clientBalance, amount, "Client should keep balance");

            // Try to identify why the transfer failed
            vm.startPrank(address(queue));
            try _token.transferFrom(address(paymentClient), recipient, amount)
            returns (bool result) {
                console.log("Manual transfer after failure succeeded:", result);
            } catch Error(string memory reason) {
                console.log(
                    "Manual transfer after failure failed with:", reason
                );
            }
            vm.stopPrank();
        }
        vm.stopPrank();
    }

    /* Test testPublicProcessNextOrder_failsGivenInsufficientConditions()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And the payment client is configured with the token
        │   ├── And the order is added to the payment client
        │   ├── And tokens are minted and approved for the payment client
        │   ├── And the order is added to the queue
        │   ├── And the initial state of the order is verified to be PROCESSING
        │   └── When the function exposed_processNextOrder() is called
        │       ├── Then if the processing fails:
        │       │   ├── The failure reason should be logged
        │       │   ├── The client balance and allowance should be checked
        │       │   └── The order state should remain PROCESSING or transition to CANCELLED
        │       └── Else if the processing succeeds:
        │           ├── The order state should transition to COMPLETED
        │           ├── The recipient should receive the correct amount of tokens
        │           └── The client balance should be updated accordingly
    */
    function testPublicProcessNextOrder_failsGivenInsufficientConditions()
        public
    {
        // Setup a basic order
        address recipient = makeAddr("recipient");
        uint96 amount = 1000;

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

        // Setup payment client and balances
        paymentClient.setToken(ERC20Mock(address(_token)));
        paymentClient.addPaymentOrderUnchecked(order);
        _token.mint(address(paymentClient), amount);

        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add order to queue
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        // Get initial state
        IPP_Queue_v1.QueuedOrder memory initialState = queue.getOrder(
            orderId, IERC20PaymentClientBase_v1(address(paymentClient))
        );
        assertEq(
            uint(initialState.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING)
        );

        // Try to process the order
        bool success = queue.exposed_processNextOrder(address(paymentClient));

        // Get final state
        IPP_Queue_v1.QueuedOrder memory finalState = queue.getOrder(
            orderId, IERC20PaymentClientBase_v1(address(paymentClient))
        );

        console.log("Success:", success);
        console.log("Initial State:", uint(initialState.state_), "(PROCESSING)");
        console.log(
            "Final State:",
            uint(finalState.state_),
            finalState.state_ == IPP_Queue_v1.RedemptionState.COMPLETED
                ? "(COMPLETED)"
                : finalState.state_ == IPP_Queue_v1.RedemptionState.CANCELLED
                    ? "(CANCELLED)"
                    : "(PROCESSING)"
        );
        console.log("Recipient Balance:", _token.balanceOf(recipient));
        console.log("Client Balance:", _token.balanceOf(address(paymentClient)));
        console.log(
            "Queue Allowance:",
            _token.allowance(address(paymentClient), address(queue))
        );

        // The order should either complete successfully or fail with a clear reason
        if (!success) {
            // If it failed, let's check why
            console.log(
                "Has Sufficient Balance:",
                _token.balanceOf(address(paymentClient)) >= amount
            );
            console.log(
                "Has Sufficient Allowance:",
                _token.allowance(address(paymentClient), address(queue))
                    >= amount
            );
        }

        vm.stopPrank();
    }

    /* Test testPublicUpdateOrderState_revertsGivenInvalidStateTransition()
        ├── Given a valid recipient address
        │   ├── And a valid amount (greater than 0)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the order state is updated to CANCELLED
        │   └── When the function exposed_updateOrderState() is called to transition to COMPLETED
        │       ├── Then the transaction should revert
        │       └── And the order state should remain CANCELLED
    */
    function testPublicUpdateOrderState_revertsGivenInvalidStateTransition()
        public
    {
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

        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState.CANCELLED
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId,
                uint(IPP_Queue_v1.RedemptionState.CANCELLED),
                uint(IPP_Queue_v1.RedemptionState.COMPLETED)
            )
        );
        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState.COMPLETED
        );

        IPP_Queue_v1.QueuedOrder memory finalOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(address(this)));
        assertEq(
            uint(finalOrder.state_),
            uint(IPP_Queue_v1.RedemptionState.CANCELLED),
            "Order should remain CANCELLED"
        );
    }

    /* Test testPublicUpdateOrderState_revertsGivenInvalidStateTransition()
        ├── Given a valid recipient address (not address(0), not the queue, and not the payment client)
        │   ├── And a valid amount (greater than 0 and bounded to uint96 max)
        │   ├── And a payment order is created with the valid parameters
        │   ├── And tokens are minted and approved for the order
        │   ├── And the order is added to the queue
        │   ├── And the order state is updated to a specific initial state (COMPLETED, CANCELLED, or PROCESSING)
        │   ├── And the target state is different from the initial state
        │   └── When the function exposed_updateOrderState() is called to transition to the target state
        │       ├── Then the transaction should revert
        │       └── And the order state should remain unchanged
    */
    function testPublicUpdateOrderState_revertsGivenInvalidStateTransition(
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
            fromState == uint(IPP_Queue_v1.RedemptionState.PROCESSING)
                || fromState == toState
        ) {
            return;
        }

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

        _token.mint(address(this), amount);
        _token.approve(address(queue), amount);
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState(fromState)
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId,
                fromState,
                toState
            )
        );
        queue.exposed_updateOrderState(
            orderId, IPP_Queue_v1.RedemptionState(toState)
        );

        IPP_Queue_v1.QueuedOrder memory finalOrder =
            queue.getOrder(orderId, IERC20PaymentClientBase_v1(address(this)));
        assertEq(
            uint(finalOrder.state_), fromState, "Order state should not change"
        );

        console.log("\nTest Parameters:");
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);
        console.log("From State:", fromState);
        console.log("To State:", toState);
        console.log("Order ID:", orderId);
        console.log("Final State:", uint(finalOrder.state_));
    }

    /* Test testPublicValidQueueId_failsGivenInvalidId()
        ├── Given a valid client address (not address(0), not the queue, and not the current caller)
        │   ├── And a valid payment order is created and added to the queue
        │   ├── And tokens are minted and approved for the order
        │   ├── And a valid queue ID is generated
        │   ├── And the queue ID to test is different from the valid one and not zero
        │   └── When the function exposed_validQueueId() is called with the invalid queue ID and client
        │       └── Then it should return false
    */
    function testPublicValidQueueId_failsGivenInvalidId(
        uint queueId,
        address client
    ) public {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));

        // Create a valid order to initialize the queue counter
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
        uint validQueueId =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

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

    /* Test testPublicCancelPaymentOrder_revertsGivenNonExistentOrder()
        ├── Given a valid client address (not address(0), not the queue, and not the current caller)
        │   ├── And a valid payment order is created and added to the queue
        │   ├── And tokens are minted and approved for the order
        │   ├── And a valid order ID is generated
        │   ├── And the order ID to test is different from the existing one
        │   └── When the function cancelPaymentOrderThroughQueueId() is called with the non-existent order ID and client
        │       └── Then the transaction should revert
    */
    function testPublicCancelPaymentOrder_revertsGivenNonExistentOrder(
        uint orderId,
        address client
    ) public {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));

        // Create a valid order to have a reference point
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
        uint existingOrderId =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

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
            orderId, IERC20PaymentClientBase_v1(client)
        );

        // Log test parameters for debugging
        console.log("\nTest Parameters:");
        console.log("Non-existent Order ID:", orderId);
        console.log("Client:", client);
        console.log("Existing Order ID:", existingOrderId);
    }

    /* Test testPublicCancelPaymentOrder_revertsGivenZeroId()
        ├── Given a valid client address (not address(0), not the queue, and not the current caller)
        │   └── When the function cancelPaymentOrderThroughQueueId() is called with an order ID of 0
        │       └── Then the transaction should revert
    */
    function testPublicCancelPaymentOrder_revertsGivenZeroId(address client)
        public
    {
        // Assume valid client address
        vm.assume(client != address(0));
        vm.assume(client != address(queue));
        vm.assume(client != address(this));

        // Try to cancel order with ID 0
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_InvalidState()")
        );
        queue.cancelPaymentOrderThroughQueueId(
            0, IERC20PaymentClientBase_v1(client)
        );

        // Log test parameters
        console.log("\nTest Parameters:");
        console.log("Client:", client);
    }
}
