// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {PP_Simple_v1, IPaymentProcessor_v1} from "src/modules/paymentProcessor/PP_Simple_v1.sol";
import {PP_Queue_v1Mock} from "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
import {PP_Simple_v1AccessMock} from "test/utils/mocks/modules/paymentProcessor/PP_Simple_v1AccessMock.sol";
import {IERC20PaymentClientBase_v1, ERC20PaymentClientBaseV1Mock, ERC20Mock} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {NonStandardTokenMock} from "test/utils/mocks/token/NonStandardTokenMock.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ModuleTest, IModule_v1, IOrchestrator_v1} from "test/modules/ModuleTest.sol";

// External
import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    /* Test testInit()
        └── Given a newly deployed contract
            └── When the function init() is called
                └── Then the orchestrator address should be set correctly.
    */
    function testInit() public override(ModuleTest) {
        assertEq(address(queue.orchestrator()), address(_orchestrator));
    }

    /* Test testSupportsInterface()
        └── Given a deployed contract
            └── When the function supportsInterface() is called with a valid interface ID
                └── Then it should return true.
    */
    function testSupportsInterface() public {
        assertTrue(
            queue.supportsInterface(type(IPaymentProcessor_v1).interfaceId)
        );
    }

    /* Test testReinitFails()
        └── Given an initialized contract
            └── When the function init() is called again
                └── Then the transaction should revert with InvalidInitialization error.
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        queue.init(_orchestrator, _METADATA, bytes(""));
    }

    /* Test testQueueOperations_GivenValidRecipientAndAmount()
        └── Given a valid recipient and amount
            └── When adding a payment order to the queue
                ├── Then the order should be added successfully
                ├── Then the queue size should be incremented
                ├── Then the queued order amount should match input
                ├── Then the queued order recipient should match input
                ├── Then the queued order client should match the sender
                └── Then the queued order timestamp should be greater than 0.
    */
    function testQueueOperations_GivenValidRecipientAndAmount(
        address recipient_,
        uint96 amount_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(amount_ > 0 && amount_ < type(uint96).max);

        // Setup
        _authorizer.setIsAuthorized(address(queue), true);
        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);

        // Create payment order without flags or data
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
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
        paymentClient.addPaymentOrderUnchecked(order);

        // Then mint tokens and approve
        _token.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);

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
        assertEq(queuedOrder.order_.recipient, recipient_, "Wrong recipient");
        assertEq(queuedOrder.order_.amount, amount_, "Wrong amount");
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

    /* Test testValidPaymentReceiver_GivenValidAddress()
    └── Given a valid recipient address
        └── When validating the payment receiver
            └── Then it should return true.
    */
    function testValidPaymentReceiver_GivenValidAddress() public {
        assertTrue(queue.exposed_validPaymentReceiver(makeAddr("valid")));
    }

    /* Test testValidPaymentReceiver_RevertGivenInvalidAddress()
        └── Given an invalid recipient address
            └── When validating the payment receiver
                └── Then it should return false.
    */
    function testValidPaymentReceiver_RevertGivenInvalidAddress() public {
        assertFalse(queue.exposed_validPaymentReceiver(address(0)));
        assertFalse(queue.exposed_validPaymentReceiver(address(queue)));
    }

    /* Test testValidTotalAmount_GivenValidAmount()
        └── Given a valid amount greater than 0
            └── When validating the total amount
                └── Then it should return true.
    */
    function testValidTotalAmount_GivenValidAmount() public {
        assertTrue(queue.exposed_validTotalAmount(100));
    }

    /* Test testValidTotalAmount_RevertGivenZeroAmount()
        └── Given an amount equal to 0
            └── When validating the total amount
                └── Then it should return false.
    */
    function testValidTotalAmount_RevertGivenZeroAmount() public {
        assertFalse(queue.exposed_validTotalAmount(0));
    }

    /* Test testValidTokenBalance_GivenSufficientBalance()
        └── Given a user with sufficient token balance
            └── When validating the token balance
                └── Then it should return true.
    */
    function testValidTokenBalance_GivenSufficientBalance() public {
        address user_ = makeAddr("user");
        deal(address(_token), user_, 1000);
        
        vm.startPrank(user_);
        assertTrue(queue.exposed_validTokenBalance(address(_token), user_, 500));
        vm.stopPrank();
    }

    /* Test testValidTokenBalance_RevertGivenInsufficientBalance()
        └── Given a user with insufficient token balance
            └── When validating the token balance
                └── Then it should return false.
    */
    function testValidTokenBalance_RevertGivenInsufficientBalance(uint96 amount_) public {
        vm.assume(amount_ > 0);
        
        address user_ = makeAddr("user");
        deal(address(_token), user_, amount_ - 1);
        
        vm.startPrank(user_);
        assertFalse(queue.exposed_validTokenBalance(address(_token), user_, amount_));
        vm.stopPrank();
    }

    /* Test testValidTokenBalance_GivenSufficientAllowance()
        └── Given a user with sufficient token balance and allowance
            └── When validating the token balance with half the approved amount
                └── Then it should return true.
    */
    function testValidTokenBalance_GivenSufficientAllowance(
        uint amount_,
        address user_
    ) public {
        vm.assume(user_ != address(0));
        vm.assume(user_ != address(queue));
        vm.assume(user_ != address(this));

        amount_ = bound(amount_, 1, 1e30);

        deal(address(_token), user_, amount_);
        vm.startPrank(user_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        assertTrue(
            queue.exposed_validTokenBalance(address(_token), user_, amount_ / 2)
        );
    }

    /* Test testValidTokenBalance_RevertGivenInsufficientAllowance()
        └── Given a user with insufficient allowance
            └── When validating the token balance with double the approved amount
                └── Then it should return false.
    */
    function testValidTokenBalance_RevertGivenInsufficientAllowance(
        uint amount_,
        address user_
    ) public {
        vm.assume(user_ != address(0));
        vm.assume(user_ != address(queue));
        vm.assume(user_ != address(this));

        amount_ = bound(amount_, 1, 1e30);

        deal(address(_token), user_, amount_);
        vm.startPrank(user_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user_, amount_ * 2)
        );
    }

    /* Test testValidTotalAmount_GivenAmount()
        └── Given any amount
            └── When validating the total amount
                └── Then it should return true for non-zero amounts and false for zero.
    */
    function testValidTotalAmount_GivenAmount(uint amount_) public {
        if (amount_ == 0) {
            assertFalse(
                queue.exposed_validTotalAmount(amount_),
                "Zero amount should be invalid."
            );
        } else {
            assertTrue(
                queue.exposed_validTotalAmount(amount_),
                "Non-zero amount should be valid."
            );
        }
    }

    /* Test testValidPaymentReceiver_GivenValidAddress()
        └── Given a valid recipient address that is not:
            ├── address(0)
            ├── queue address
            ├── orchestrator address
            └── token address
                └── When validating the payment receiver
                    └── Then it should return true.
    */
    function testValidPaymentReceiver_GivenValidAddress(address receiver_) public {
        vm.assume(receiver_ != address(0));
        vm.assume(receiver_ != address(queue));
        vm.assume(receiver_ != address(_orchestrator));
        vm.assume(receiver_ != address(_orchestrator.fundingManager().token()));

        assertTrue(
            queue.exposed_validPaymentReceiver(receiver_),
            "Valid receiver marked as invalid."
        );
    }

    /* Test testValidTokenBalance_GivenBalanceAndAmount()
        └── Given a user with a token balance and approval
            └── When validating the token balance
                ├── If balance is greater than or equal to amount
                │   └── Then it should return true.
                └── If balance is less than amount
                    └── Then it should return false.
    */
    function testValidTokenBalance_GivenBalanceAndAmount(
        uint balance_,
        uint amount_
    ) public {
        vm.assume(amount_ > 0);

        address user_ = makeAddr("user");
        deal(address(_token), user_, balance_);

        vm.startPrank(user_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        bool isValid_ = queue.exposed_validTokenBalance(
            address(_token),
            user_,
            amount_
        );

        if (balance_ >= amount_) {
            assertTrue(isValid_, "Sufficient balance marked as invalid.");
        } else {
            assertFalse(isValid_, "Insufficient balance marked as valid.");
        }
    }

    /* Test testGetPaymentQueueId_GivenFlagsAndData()
        └── Given flags and data for queue ID retrieval
            └── When validating the payment queue ID
                ├── If ORDER_ID bit is set and data exists
                │   └── Then it should return the correct queue ID.
                └── If ORDER_ID bit is not set or data is empty
                    └── Then it should return 0.
    */
    function testGetPaymentQueueId_GivenFlagsAndData(
        uint queueId_,
        uint8 flagBits_,
        uint8 dataLength_
    ) public {
        dataLength_ = uint8(bound(dataLength_, 0, 10));
        bytes32 flags_ = bytes32(uint(flagBits_));

        bytes32[] memory data_ = new bytes32[](dataLength_);
        if (dataLength_ > 0) {
            data_[0] = bytes32(queueId_);
        }

        uint retrievedId_ = queue.exposed_getPaymentQueueId(flags_, data_);

        if ((flagBits_ & 1 == 1) && dataLength_ > 0) {
            assertEq(
                retrievedId_,
                queueId_,
                "Queue ID mismatch when flag is set and data exists."
            );
        } else {
            assertEq(
                retrievedId_,
                0,
                "Should return 0 when flag is not set or data is empty."
            );
        }
    }

    /* Test testGetQueueSizeForClient_GivenEmptyAndFilledQueue()
        └── Given a client's queue
            └── When checking the queue size
                ├── Then it should be 0 initially.
                ├── Then it should be 1 after adding an order.
                └── Then it should be 0 after canceling the order.
    */
    function testGetQueueSizeForClient_GivenEmptyAndFilledQueue() public {
        assertEq(
            queue.getQueueSizeForClient(address(this)),
            0,
            "Initial queue size should be 0."
        );

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

        _token.mint(address(this), 100);
        _token.approve(address(queue), 100);
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueSizeForClient(address(this)),
            1,
            "Queue size should be 1 after adding."
        );

        queue.cancelPaymentOrderThroughQueueId(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueSizeForClient(address(this)),
            0,
            "Queue size should be 0 after canceling."
        );
    }

    /* Test testGetQueueSizeForClient_GivenMultipleOrders()
        └── Given a valid client with multiple orders
            └── When managing the queue
                ├── Then it should be 0 initially.
                ├── Then it should match numOrders after adding orders.
                ├── Then it should decrease after each cancellation.
                └── Then it should be 0 for non-existent client.
    */
    function testGetQueueSizeForClient_GivenMultipleOrders(
        address client_,
        uint8 numOrders_
    ) public {
        vm.assume(client_ != address(0));
        vm.assume(client_ != address(queue));
        vm.assume(client_ != address(this));

        numOrders_ = uint8(bound(uint(numOrders_), 1, 10));

        assertEq(
            queue.getQueueSizeForClient(client_),
            0,
            "Initial queue size should be 0."
        );

        uint[] memory orderIds_ = new uint[](numOrders_);

        for (uint8 i = 0; i < numOrders_; i++) {
            IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: makeAddr(string.concat("recipient", vm.toString(i))),
                    amount: 100,
                    paymentToken: address(_token),
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: bytes32(0),
                    data: new bytes32[](0)
                });

            _token.mint(client_, 100);
            vm.startPrank(client_);
            _token.approve(address(queue), 100);
            vm.stopPrank();

            orderIds_[i] = queue.exposed_addPaymentOrderToQueue(order_, client_);
        }

        assertEq(
            queue.getQueueSizeForClient(client_),
            numOrders_,
            "Queue size should match number of orders added."
        );

        for (uint8 i = 0; i < numOrders_; i++) {
            queue.cancelPaymentOrderThroughQueueId(
                orderIds_[i],
                IERC20PaymentClientBase_v1(client_)
            );

            assertEq(
                queue.getQueueSizeForClient(client_),
                numOrders_ - (i + 1),
                "Queue size should decrease after each cancellation."
            );
        }

        assertEq(
            queue.getQueueSizeForClient(client_),
            0,
            "Final queue size should be 0."
        );

        assertEq(
            queue.getQueueSizeForClient(address(0)),
            0,
            "Queue size should be 0 for non-existent client."
        );
    }

    /* Test testGetOrder_GivenValidOrderId()
        └── Given a valid order ID
            └── When retrieving the order
                ├── Then it should return the correct order details.
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                └── Then state should be QUEUED.
    */
    function testGetOrder_GivenValidOrderId() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queuedOrder_.order_.recipient,
            recipient_,
            "Recipient should match."
        );
        assertEq(
            queuedOrder_.order_.amount,
            amount_,
            "Amount should match."
        );
        assertEq(
            queuedOrder_.order_.paymentToken,
            address(_token),
            "Token should match."
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "State should be PROCESSING."
        );
    }

    /* Test testGetOrder_GivenValidOrderFuzz()
        └── Given a valid order with fuzzed inputs
            └── When retrieving the order
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                ├── Then origin chain ID should match.
                ├── Then target chain ID should match.
                ├── Then state should be PROCESSING.
                ├── Then order ID should match.
                └── Then client should match.
    */
    function testGetOrder_GivenValidOrder(
        address client_,
        address recipient_,
        uint96 amount_,
        uint originChainId_,
        uint targetChainId_
    ) public {
        vm.assume(client_ != address(0));
        vm.assume(recipient_ != address(0));
        vm.assume(client_ != address(queue));
        vm.assume(recipient_ != address(queue));
        vm.assume(client_ != recipient_);

        amount_ = uint96(bound(uint(amount_), 1, 1e30));
        originChainId_ = bound(originChainId_, 1, 1e6);
        targetChainId_ = bound(targetChainId_, 1, 1e6);

        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient_,
                amount: amount_,
                paymentToken: address(_token),
                originChainId: originChainId_,
                targetChainId: targetChainId_,
                flags: bytes32(0),
                data: new bytes32[](0)
            });

        _token.mint(client_, amount_);
        vm.startPrank(client_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, client_);

        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_,
            IERC20PaymentClientBase_v1(client_)
        );

        assertEq(
            queuedOrder_.order_.recipient,
            recipient_,
            "Recipient should match."
        );
        assertEq(
            queuedOrder_.order_.amount,
            amount_,
            "Amount should match."
        );
        assertEq(
            queuedOrder_.order_.paymentToken,
            address(_token),
            "Token should match."
        );
        assertEq(
            queuedOrder_.order_.originChainId,
            originChainId_,
            "Origin chain ID should match."
        );
        assertEq(
            queuedOrder_.order_.targetChainId,
            targetChainId_,
            "Target chain ID should match."
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSING),
            "State should be PROCESSING."
        );
        assertEq(
            queuedOrder_.orderId_,
            orderId_,
            "Order ID should match."
        );
        assertEq(
            queuedOrder_.client_,
            client_,
            "Client should match."
        );
    }

    /* Test testGetOrder_RevertGivenInvalidOrderId()
        └── Given an invalid order ID
            └── When retrieving the order
                └── Then it should revert with Module__PP_Queue_InvalidOrderId.
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

    /* Test testGetOrder_GivenCancelledOrder()
        └── Given a cancelled order
            └── When retrieving the order
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                └── Then state should be CANCELLED.
    */
    function testGetOrder_GivenCancelledOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        queue.cancelPaymentOrderThroughQueueId(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queuedOrder_.order_.recipient,
            recipient_,
            "Recipient should match."
        );
        assertEq(
            queuedOrder_.order_.amount,
            amount_,
            "Amount should match."
        );
        assertEq(
            queuedOrder_.order_.paymentToken,
            address(_token),
            "Token should match."
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.CANCELLED),
            "State should be CANCELLED."
        );
    }

    /* Test testGetOrder_GivenProcessedOrder()
        └── Given a processed order
            └── When retrieving the order
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                └── Then state should be COMPLETED.
    */
    function testGetOrder_GivenProcessedOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        queue.exposed_updateOrderState(
            orderId_,
            IPP_Queue_v1.RedemptionState.COMPLETED
        );
        queue.exposed_removeFromQueue(orderId_);

        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queuedOrder_.order_.recipient,
            recipient_,
            "Recipient should match."
        );
        assertEq(
            queuedOrder_.order_.amount,
            amount_,
            "Amount should match."
        );
        assertEq(
            queuedOrder_.order_.paymentToken,
            address(_token),
            "Token should match."
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.COMPLETED),
            "State should be COMPLETED."
        );
    }

    /* Test testGetOrderQueue_GivenEmptyQueue()
        └── Given an empty queue
            └── When retrieving the queue
                └── Then it should return an empty array.
    */
    function testGetOrderQueue_GivenEmptyQueue() public {
        uint[] memory orders_ = queue.getOrderQueue(address(this));
        assertEq(orders_.length, 0, "Queue should be empty.");
    }

    /* Test testGetOrderQueue_GivenSingleOrder()
        └── Given a queue with a single order
            └── When retrieving the queue
                └── Then it should return array with one order ID.
    */
    function testGetOrderQueue_GivenSingleOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        uint[] memory orders_ = queue.getOrderQueue(address(this));
        assertEq(orders_.length, 1, "Queue should have one order.");
        assertEq(orders_[0], orderId_, "Order ID should match.");
    }

    /* Test testGetOrderQueue_GivenMultipleOrders()
        └── Given a queue with multiple orders
            └── When retrieving the queue
                ├── Then array length should match order count.
                └── Then all order IDs should match.
    */
    function testGetOrderQueue_GivenMultipleOrders(uint8 orderCount_) public {
        orderCount_ = uint8(bound(orderCount_, 2, 5));
        uint[] memory orderIds_ = new uint[](orderCount_);

        for (uint i_; i_ < orderCount_; i_++) {
            IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: makeAddr(string.concat("recipient", vm.toString(i_))),
                    amount: 100,
                    paymentToken: address(_token),
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: bytes32(0),
                    data: new bytes32[](0)
                });

            _token.mint(address(this), 100);
            _token.approve(address(queue), 100);
            orderIds_[i_] = queue.exposed_addPaymentOrderToQueue(
                order_,
                address(this)
            );
        }

        uint[] memory queueOrders_ = queue.getOrderQueue(address(this));
        assertEq(
            queueOrders_.length,
            orderCount_,
            "Queue length should match order count."
        );

        for (uint i_; i_ < orderCount_; i_++) {
            assertEq(
                queueOrders_[i_],
                orderIds_[i_],
                "Order ID should match."
            );
        }
    }

    /* Test testGetOrderQueue_GivenNonExistentClient()
        └── Given a non-existent client
            └── When retrieving the queue
                └── Then it should return an empty array.
    */
    function testGetOrderQueue_GivenNonExistentClient() public {
        address nonExistentClient_ = makeAddr("nonExistentClient");
        uint[] memory orders_ = queue.getOrderQueue(nonExistentClient_);
        assertEq(orders_.length, 0, "Queue should be empty.");
    }

    /* Test testAddPaymentOrderToQueue_RevertGivenInvalidOrder()
        └── Given an order with invalid recipient
            └── When adding order to queue
                └── Then it should revert with Module__PP_Queue_QueueOperationFailed.
    */
    function testAddPaymentOrderToQueue_RevertGivenInvalidOrder() public {
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: address(0),
                amount: 100,
                paymentToken: address(_token),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: bytes32(0),
                data: new bytes32[](0)
            });

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)",
                address(this)
            )
        );
        queue.exposed_addPaymentOrderToQueue(order_, address(this));
    }

    /* Test testQueueOperations_GivenValidInputs()
        └── Given valid orders
            └── When performing queue operations
                ├── Then orders should be added correctly.
                ├── Then orders should be cancelled correctly.
                └── Then queue should be empty after operations.
    */
    function testQueueOperations_GivenValidInputs() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        uint[] memory queueBefore_ = queue.getOrderQueue(address(this));
        assertEq(queueBefore_.length, 1, "Queue should have one order.");
        assertEq(queueBefore_[0], orderId_, "Order ID should match.");

        queue.cancelPaymentOrderThroughQueueId(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        uint[] memory queueAfter_ = queue.getOrderQueue(address(this));
        assertEq(queueAfter_.length, 0, "Queue should be empty after cancel.");
    }

    /* Test testGetQueueHead_RevertGivenUninitializedQueue()
        └── Given an uninitialized queue
            └── When getting queue head
                └── Then it should revert with Module__PP_Queue_QueueOperationFailed.
    */
    function testGetQueueHead_RevertGivenUninitializedQueue() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)",
                address(this)
            )
        );
        queue.getQueueHead(address(this));
    }

    /* Test testGetQueueHead_GivenSingleOrder()
        └── Given a queue with one order
            └── When getting queue head
                └── Then it should return first order ID.
    */
    function testGetQueueHead_GivenSingleOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueHead(address(this)),
            orderId_,
            "Head should be first order ID."
        );
    }

    /* Test testGetQueueHead_GivenMultipleOrders()
        └── Given a queue with multiple orders
            └── When getting queue head
                └── Then it should return first order ID.
    */
    function testGetQueueHead_GivenMultipleOrders() public {
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
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueHead(address(this)),
            firstOrderId_,
            "Head should be first order ID."
        );
    }

    /* Test testGetQueueHead_GivenPartiallyProcessedQueue()
        └── Given a queue with multiple orders and first cancelled
            └── When getting queue head
                └── Then it should return second order ID.
    */
    function testGetQueueHead_GivenPartiallyProcessedQueue() public {
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
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueHead(address(this)),
            2,
            "Head should be second order ID."
        );
    }

    /* Test testGetQueueHead_GivenFullyProcessedQueue()
        └── Given a queue with all orders cancelled
            └── When getting queue head
                └── Then it should return sentinel value.
    */
    function testGetQueueHead_GivenFullyProcessedQueue() public {
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
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint secondOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_,
            IERC20PaymentClientBase_v1(address(this))
        );
        queue.cancelPaymentOrderThroughQueueId(
            secondOrderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueHead(address(this)),
            type(uint).max,
            "Head should be sentinel value."
        );
    }

    /* Test testGetQueueTail_GivenUninitializedQueue()
        └── Given an uninitialized queue
            └── When getting queue tail
                └── Then it should return sentinel value.
    */
    function testGetQueueTail_GivenUninitializedQueue() public {
        assertEq(
            queue.getQueueTail(address(this)),
            type(uint).max,
            "Tail should be sentinel value."
        );
    }

    /* Test testGetQueueTail_GivenSingleOrder()
        └── Given a queue with one order
            └── When getting queue tail
                └── Then it should return first order ID.
    */
    function testGetQueueTail_GivenSingleOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueTail(address(this)),
            orderId_,
            "Tail should be first order ID."
        );
    }

    /* Test testGetQueueTail_GivenMultipleOrders()
        └── Given a queue with multiple orders
            └── When getting queue tail
                └── Then it should return last order ID.
    */
    function testGetQueueTail_GivenMultipleOrders() public {
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

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint lastOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        assertEq(
            queue.getQueueTail(address(this)),
            lastOrderId_,
            "Tail should be last order ID."
        );
    }

    /* Test testGetQueueTail_GivenPartiallyProcessedQueue()
        └── Given a queue with multiple orders and first cancelled
            └── When getting queue tail
                └── Then it should return last order ID.
    */
    function testGetQueueTail_GivenPartiallyProcessedQueue() public {
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
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint lastOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueTail(address(this)),
            lastOrderId_,
            "Tail should be last order ID."
        );
    }

    /* Test testGetQueueTail_GivenFullyProcessedQueue()
        └── Given a queue with all orders cancelled
            └── When getting queue tail
                └── Then it should return sentinel value.
    */
    function testGetQueueTail_GivenFullyProcessedQueue() public {
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
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint secondOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order_,
            address(this)
        );

        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_,
            IERC20PaymentClientBase_v1(address(this))
        );
        queue.cancelPaymentOrderThroughQueueId(
            secondOrderId_,
            IERC20PaymentClientBase_v1(address(this))
        );

        assertEq(
            queue.getQueueTail(address(this)),
            type(uint).max,
            "Tail should be sentinel value."
        );
    }

    /* Test testGetQueueOperatorRole_GivenValidRole()
        └── Given a queue operator role
            └── When getting the role
                └── Then it should return correct role hash.
    */
    function testGetQueueOperatorRole_GivenValidRole() public {
        bytes32 expectedRole_ = keccak256("QUEUE_OPERATOR_ROLE");
        assertEq(
            queue.getQueueOperatorRole(),
            expectedRole_,
            "Role hash should match."
        );
    }

    /* Test testProcessNextOrder_GivenValidOrder()
        └── Given a valid order in queue
            └── When processing next order
                ├── Then it should succeed.
                └── Then order should be processed.
    */
    function testProcessNextOrder_GivenValidOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        vm.prank(address(this));
        bool success_ = queue.exposed_processNextOrder(address(this));
        assertTrue(success_, "Order processing should succeed.");
    }

    /* Test testProcessNextOrder_GivenEmptyQueue()
        └── Given an empty queue
            └── When processing next order
                └── Then it should return false.
    */
    function testProcessNextOrder_GivenEmptyQueue() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.exposed_removeFromQueue(orderId_);

        vm.prank(address(this));
        bool success_ = queue.exposed_processNextOrder(address(this));
        assertFalse(success_, "Processing empty queue should fail.");
    }

    /* Test testExecutePaymentTransfer_GivenValidOrder()
        └── Given a valid payment order
            └── When executing transfer
                ├── Then it should succeed.
                ├── Then recipient should receive tokens.
                └── Then queue balance should decrease.
    */
    function testExecutePaymentTransfer_GivenValidOrder() public {
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

        _token.mint(address(queue), amount_);
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.exposed_executePaymentTransfer(orderId_);

        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive tokens."
        );
        assertEq(
            _token.balanceOf(address(queue)),
            0,
            "Queue balance should be zero."
        );
    }

    /* Test testExecutePaymentTransfer_RevertGivenInvalidOrder()
        └── Given an order with insufficient balance
            └── When executing transfer
                └── Then it should revert with Module__PP_Queue_TransferFailed.
    */
    function testExecutePaymentTransfer_RevertGivenInvalidOrder() public {
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

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_TransferFailed(address,uint256)",
                recipient_,
                amount_
            )
        );
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.exposed_executePaymentTransfer(orderId_);
    }

    /* Test testExecutePaymentTransfer_RevertGivenInsufficientBalance()
        └── Given an order with insufficient balance
            └── When executing transfer
                └── Then it should revert with Module__PP_Queue_TransferFailed.
    */
    function testExecutePaymentTransfer_RevertGivenInsufficientBalance() public {
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

        _token.mint(address(queue), amount_ - 1);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_TransferFailed(address,uint256)",
                recipient_,
                amount_
            )
        );
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.exposed_executePaymentTransfer(orderId_);
    }

    /* Test testOrderExists_GivenValidOrder()
        └── Given a valid order in queue
            └── When checking if order exists
                └── Then it should return true.
    */
    function testOrderExists_GivenValidOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertTrue(
            queue.exposed_orderExists(
                orderId_,
                IERC20PaymentClientBase_v1(address(this))
            ),
            "Order should exist."
        );
    }

    /* Test testOrderExists_GivenInvalidOrder()
        └── Given a non-existent order ID
            └── When checking if order exists
                └── Then it should return false.
    */
    function testOrderExists_GivenInvalidOrder() public {
        assertFalse(
            queue.exposed_orderExists(
                999,
                IERC20PaymentClientBase_v1(address(this))
            ),
            "Invalid order should not exist."
        );
    }

    /* Test testOrderExists_GivenInvalidClient()
        └── Given a non-existent client
            └── When checking if order exists
                └── Then it should return false.
    */
    function testOrderExists_GivenInvalidClient() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        address invalidClient_ = makeAddr("invalidClient");
        assertFalse(
            queue.exposed_orderExists(
                orderId_,
                IERC20PaymentClientBase_v1(invalidClient_)
            ),
            "Order should not exist for invalid client."
        );
    }

    /* Test testValidQueueId_GivenValidId()
        └── Given a valid queue ID
            └── When checking if ID is valid
                └── Then it should return true.
    */
    function testValidQueueId_GivenValidId() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertTrue(
            queue.exposed_validQueueId(orderId_, address(this)),
            "Queue ID should be valid."
        );
    }

    /* Test testUpdateOrderState_GivenValidOrder()
        └── Given a valid order in queue
            └── When updating order state
                ├── Then it should update state.
                └── Then state should match expected value.
    */
    function testUpdateOrderState_GivenValidOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        queue.exposed_updateOrderState(
            orderId_,
            IPP_Queue_v1.RedemptionState.COMPLETED
        );

        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_,
            IERC20PaymentClientBase_v1(address(this))
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.COMPLETED),
            "State should be COMPLETED."
        );
    }

    /* Test testRemoveFromQueue_GivenValidOrder()
        └── Given a valid order in queue
            └── When removing order
                ├── Then it should be removed.
                └── Then queue should be empty.
    */
    function testRemoveFromQueue_GivenValidOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        queue.exposed_removeFromQueue(orderId_);

        uint[] memory orders_ = queue.getOrderQueue(address(this));
        assertEq(orders_.length, 0, "Queue should be empty.");
    }

    /* Test testProcessNextOrder_RevertGivenNonStandardToken()
        └── Given an order with non-standard token
            └── When processing next order
                └── Then it should revert with Module__PP_Queue_TransferFailed.
    */
    function testProcessNextOrder_RevertGivenNonStandardToken() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        NonStandardTokenMock nonStandardToken_ = new NonStandardTokenMock();
        
        IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient_,
                amount: amount_,
                paymentToken: address(nonStandardToken_),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: bytes32(0),
                data: new bytes32[](0)
            });

        nonStandardToken_.mint(address(this), amount_);
        vm.prank(address(this));
        nonStandardToken_.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_TransferFailed(address,uint256)",
                recipient_,
                amount_
            )
        );
        queue.exposed_processNextOrder(address(this));
    }

    /* Test testClaimPreviouslyUnclaimable_GivenValidConditions()
        └── Given a previously unclaimable order
            └── When claiming order
                ├── Then it should succeed.
                └── Then recipient should receive tokens.
    */
    function testClaimPreviouslyUnclaimable_GivenValidConditions() public {
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

        _token.mint(address(queue), amount_);
        queue.exposed_addUnclaimableOrder(order_, address(this));
        queue.claimPreviouslyUnclaimable(
            address(this),
            address(_token),
            recipient_
        );

        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive tokens."
        );
    }

    /* Test testClaimPreviouslyUnclaimable_GivenMultipleAmounts()
        └── Given multiple unclaimable orders
            └── When claiming orders
                ├── Then all claims should succeed.
                └── Then recipients should receive correct amounts.
    */
    function testClaimPreviouslyUnclaimable_GivenMultipleAmounts() public {
        address[] memory recipients_ = new address[](3);
        uint96[] memory amounts_ = new uint96[](3);
        
        for (uint i_; i_ < 3; i_++) {
            recipients_[i_] = makeAddr(string.concat("recipient", vm.toString(i_)));
            amounts_[i_] = uint96((i_ + 1) * 100);
            
            IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients_[i_],
                    amount: amounts_[i_],
                    paymentToken: address(_token),
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: bytes32(0),
                    data: new bytes32[](0)
                });

            _token.mint(address(queue), amounts_[i_]);
            queue.exposed_addUnclaimableOrder(order_, address(this));
            queue.claimPreviouslyUnclaimable(
                address(this),
                address(_token),
                recipients_[i_]
            );

            assertEq(
                _token.balanceOf(recipients_[i_]),
                amounts_[i_],
                "Recipient should receive correct amount."
            );
        }
    }

    /* Test testExecutePaymentQueue_GivenMultipleOrders()
        └── Given multiple valid orders in queue
            └── When executing payment queue
                ├── Then all orders should be processed.
                └── Then recipients should receive correct amounts.
    */
    function testExecutePaymentQueue_GivenMultipleOrders() public {
        address[] memory recipients_ = new address[](3);
        uint96[] memory amounts_ = new uint96[](3);
        uint totalAmount_;
        
        for (uint i_; i_ < 3; i_++) {
            recipients_[i_] = makeAddr(string.concat("recipient", vm.toString(i_)));
            amounts_[i_] = uint96((i_ + 1) * 100);
            totalAmount_ += amounts_[i_];
            
            IERC20PaymentClientBase_v1.PaymentOrder memory order_ =
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients_[i_],
                    amount: amounts_[i_],
                    paymentToken: address(_token),
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: bytes32(0),
                    data: new bytes32[](0)
                });

            _token.mint(address(this), amounts_[i_]);
            _token.approve(address(queue), amounts_[i_]);
            queue.exposed_addPaymentOrderToQueue(order_, address(this));
        }

        queue.exposed_executePaymentQueue(address(this));

        for (uint i_; i_ < 3; i_++) {
            assertEq(
                _token.balanceOf(recipients_[i_]),
                amounts_[i_],
                "Recipient should receive correct amount."
            );
        }
    }

    /* Test testCancelPaymentOrder_RevertGivenCompletedOrder()
        └── Given a completed order
            └── When attempting to cancel
                └── Then it should revert with Module__PP_Queue_InvalidStateTransition.
    */
    function testCancelPaymentOrder_RevertGivenCompletedOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.exposed_executePaymentQueue(address(this));

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId_,
                uint8(IPP_Queue_v1.RedemptionState.COMPLETED),
                uint8(IPP_Queue_v1.RedemptionState.CANCELLED)
            )
        );
        queue.cancelPaymentOrderThroughQueueId(orderId_, IERC20PaymentClientBase_v1(address(this)));
    }

    /* Test testCancelPaymentOrder_RevertGivenCancelledOrder()
        └── Given a cancelled order
            └── When attempting to cancel again
                └── Then it should revert with Module__PP_Queue_InvalidStateTransition.
    */
    function testCancelPaymentOrder_RevertGivenCancelledOrder() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.cancelPaymentOrderThroughQueueId(orderId_, IERC20PaymentClientBase_v1(address(this)));

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId_,
                uint8(IPP_Queue_v1.RedemptionState.CANCELLED),
                uint8(IPP_Queue_v1.RedemptionState.CANCELLED)
            )
        );
        queue.cancelPaymentOrderThroughQueueId(orderId_, IERC20PaymentClientBase_v1(address(this)));
    }

    /* Test testOrderExists_GivenDifferentStates()
        └── Given orders in different states
            └── When checking existence
                ├── Then non-existent order returns false.
                ├── Then existing order returns true.
                ├── Then cancelled order returns true.
                └── Then completed order returns true.
    */
    function testOrderExists_GivenDifferentStates() public {
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

        assertFalse(
            queue.exposed_orderExists(999, IERC20PaymentClientBase_v1(address(this))),
            "Non-existent order should return false."
        );

        _token.mint(address(this), amount_ * 2);
        _token.approve(address(queue), amount_ * 2);
        
        uint orderId1_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        assertTrue(
            queue.exposed_orderExists(orderId1_, IERC20PaymentClientBase_v1(address(this))),
            "Existing order should return true."
        );

        queue.exposed_updateOrderState(
            orderId1_,
            IPP_Queue_v1.RedemptionState.CANCELLED
        );
        assertTrue(
            queue.exposed_orderExists(orderId1_, IERC20PaymentClientBase_v1(address(this))),
            "Cancelled order should return true."
        );

        uint orderId2_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));
        queue.exposed_executePaymentQueue(address(this));
        assertTrue(
            queue.exposed_orderExists(orderId2_, IERC20PaymentClientBase_v1(address(this))),
            "Completed order should return true."
        );
    }

    /* Test testProcessNextOrder_RevertGivenInsufficientBalance()
        └── Given order with insufficient balance
            └── When processing next order
                └── Then it should revert with Module__PP_Queue_TransferFailed.
    */
    function testProcessNextOrder_RevertGivenInsufficientBalance() public {
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

        _token.mint(address(this), amount_ - 1);
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order_, address(this));

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_TransferFailed(address,uint256)",
                recipient_,
                amount_
            )
        );
        queue.exposed_processNextOrder(address(this));
    }

    /* Test testUpdateOrderState_RevertGivenInvalidTransition()
        └── Given a cancelled order
            └── When updating to completed state
                └── Then it should revert with Module__PP_Queue_InvalidStateTransition.
    */
    function testUpdateOrderState_RevertGivenInvalidTransition() public {
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
        uint orderId_ = queue.exposed_addPaymentOrderToQueue(order_, address(this));

        queue.exposed_updateOrderState(
            orderId_,
            IPP_Queue_v1.RedemptionState.CANCELLED
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId_,
                uint8(IPP_Queue_v1.RedemptionState.CANCELLED),
                uint8(IPP_Queue_v1.RedemptionState.COMPLETED)
            )
        );
        queue.exposed_updateOrderState(
            orderId_,
            IPP_Queue_v1.RedemptionState.COMPLETED
        );
    }

    /* Test testValidQueueId_RevertGivenInvalidId()
        └── Given an invalid queue ID
            └── When validating ID
                └── Then it should return false.
    */
    function testValidQueueId_RevertGivenInvalidId() public {
        assertFalse(
            queue.exposed_validQueueId(999, address(this)),
            "Invalid queue ID should return false."
        );
    }

    /* Test testCancelPaymentOrder_RevertGivenNonExistentOrder()
        └── Given a non-existent order ID
            └── When cancelling order
                └── Then it should revert with Module__PP_Queue_InvalidOrderId.
    */
    function testCancelPaymentOrder_RevertGivenNonExistentOrder() public {
        uint nonExistentOrderId_ = 999;

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                nonExistentOrderId_
            )
        );
        queue.cancelPaymentOrderThroughQueueId(nonExistentOrderId_, IERC20PaymentClientBase_v1(address(this)));
    }

    /* Test testCancelPaymentOrder_RevertGivenZeroId()
        └── Given order ID zero
            └── When cancelling order
                └── Then it should revert with Module__PP_Queue_InvalidOrderId.
    */
    function testCancelPaymentOrder_RevertGivenZeroId() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                0
            )
        );
        queue.cancelPaymentOrderThroughQueueId(0, IERC20PaymentClientBase_v1(address(this)));
    }
}
