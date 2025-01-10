// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {
    ERC20Issuance_Blacklist_v1,
    IERC20Issuance_Blacklist_v1
} from "@ex/token/ERC20Issuance_blacklist_v1.sol";
import {ERC20Issuance_Blacklist_v1_Exposed} from
    "test/external/ERC20Issuance_blacklist_v1_exposed.sol";

/**
 * @title ERC20Issuance_Blacklist_v1_Test
 * @notice Test contract for ERC20Issuance_Blacklist_v1
 */
contract ERC20Issuance_Blacklist_v1_Test is Test {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Storage
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    ERC20Issuance_Blacklist_v1_Exposed token;

    address admin;
    address blacklistManager;
    address user;
    address user2;

    uint constant BATCH_LIMIT = 200;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Setup
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    function setUp() public {
        admin = makeAddr("admin");
        blacklistManager = makeAddr("blacklistManager");
        user = makeAddr("user");
        user2 = makeAddr("user2");

        vm.startPrank(admin);

        token = new ERC20Issuance_Blacklist_v1_Exposed(
            "Exposed Blacklist Token",
            "EBLT",
            18,
            1000 ether,
            admin,
            blacklistManager
        );

        // Set up blacklist managers
        token.exposed_setBlacklistManager(blacklistManager, true);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Feature: Authorization for Blacklist Modification
    // Scenario: Verifying caller authorization for modifying the blacklist
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /*  Test: Add to blacklist by authorized manager
        ├── Given: the caller is the blacklist manager
        └── When: adding an address to the blacklist
            └── Then: the address should be successfully blacklisted
            └── Then: isBlacklisted should return true for that address
    */
    function testAddToBlacklist_GivenCallerIsBlacklistManager() public {
        vm.prank(blacklistManager);
        token.addToBlacklist(user);

        assertTrue(token.isBlacklisted(user), "User should be blacklisted");
    }

    /*  Test: Remove from blacklist by authorized manager
        ├── Given: the caller is the blacklist manager
        │   └── And: an address is already blacklisted
        └── When: removing the address from the blacklist
            └── Then: the address should be successfully removed
            └── Then: isBlacklisted should return false for that address
    */
    function testRemoveFromBlacklist_GivenCallerIsBlacklistManager() public {
        vm.startPrank(blacklistManager);
        token.addToBlacklist(user);

        token.removeFromBlacklist(user);
        vm.stopPrank();

        assertFalse(token.isBlacklisted(user), "User should not be blacklisted");
    }

    /*  Test: Unauthorized address cannot add to blacklist
        ├── Given: the caller is not the blacklist manager
        │   └── And: the caller is not address(0)
        │   └── And: the caller is not the admin
        └── When: attempting to add an address to the blacklist
            └── Then: it should revert with NotBlacklistManager error
    */
    function testAddToBlacklist_revertGivenCallerIsNotBlacklistManager(
        address unauthorized
    ) public {
        vm.assume(unauthorized != blacklistManager);
        vm.assume(unauthorized != address(0));
        vm.assume(unauthorized != admin);

        vm.prank(unauthorized);
        vm.expectRevert(
            IERC20Issuance_Blacklist_v1
                .ERC20Issuance_Blacklist_NotBlacklistManager
                .selector
        );
        token.addToBlacklist(user);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Feature: Individual Blacklist Address
    // Scenario: Handling addition or removal of an address from the blacklist
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /*  Test: Add to blacklist when already blacklisted
        ├── Given: an address is already blacklisted
        └── When: attempting to blacklist it again
            └── Then: the operation should succeed (idempotent)
            └── Then: the address should remain blacklisted
    */
    function testAddToBlacklist_GivenAddressAlreadyBlacklisted(address user_)
        public
    {
        vm.assume(user_ != address(0));

        vm.startPrank(blacklistManager);
        token.addToBlacklist(user_);

        token.addToBlacklist(user_);
        vm.stopPrank();

        assertTrue(
            token.isBlacklisted(user_), "User should still be blacklisted"
        );
    }

    /*  Test: Add to blacklist when not blacklisted
        ├── Given: an address is not blacklisted
        └── When: attempting to blacklist it
            └── Then: the address should be successfully blacklisted
            └── Then: isBlacklisted should return true for that address
    */
    function testAddToBlacklist_GivenAddressNotBlacklisted(address user_)
        public
    {
        vm.assume(user_ != address(0));

        assertFalse(
            token.isBlacklisted(user_),
            "User should not be blacklisted initially"
        );

        vm.prank(blacklistManager);
        token.addToBlacklist(user_);

        assertTrue(token.isBlacklisted(user_), "User should be blacklisted");
    }

    /*  Test: Remove from blacklist when not blacklisted
        ├── Given: an address is not blacklisted
        └── When: attempting to remove it from blacklist
            └── Then: the operation should succeed (idempotent)
            └── Then: the address should remain non-blacklisted
    */
    function testRemoveFromBlacklist_GivenAddressNotBlacklisted(address user_)
        public
    {
        vm.assume(user_ != address(0));

        assertFalse(
            token.isBlacklisted(user_),
            "User should not be blacklisted initially"
        );

        vm.prank(blacklistManager);
        token.removeFromBlacklist(user_);

        assertFalse(
            token.isBlacklisted(user_), "User should still not be blacklisted"
        );
    }

    /*  Test: Remove from blacklist when blacklisted
        ├── Given: an address is blacklisted
        └── When: attempting to remove it from blacklist
            └── Then: the address should be successfully removed
            └── Then: isBlacklisted should return false for that address
    */
    function testRemoveFromBlacklist_GivenAddressBlacklisted(address user_)
        public
    {
        vm.assume(user_ != address(0));

        vm.startPrank(blacklistManager);
        token.addToBlacklist(user_);

        token.removeFromBlacklist(user_);
        vm.stopPrank();

        assertFalse(
            token.isBlacklisted(user_), "User should not be blacklisted"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Feature: Batch Blacklist Address Management
    // Scenario: Handling batch addition or removal of addresses from the blacklist
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /*  Test: Batch blacklist with mixed status
        ├── Given: a batch of three addresses
        │   └── And: the first address is already blacklisted
        │   └── And: the second and third addresses are not blacklisted
        ├── When: batch adding all addresses to blacklist
        │   └── Then: the operation should succeed
        │   └── Then: all addresses should end up blacklisted
        │   └── Then: the previously blacklisted address should remain blacklisted
        └── When: checking each address status
            └── Then: isBlacklisted should return true for all addresses
    */
    function testBatchAddToBlacklist_GivenSomeAddressesAlreadyBlacklisted()
        public
    {
        address[] memory addresses = _generateAddresses(3);
        vm.startPrank(blacklistManager);
        token.addToBlacklist(addresses[0]);

        token.addToBlacklistBatched(addresses);
        vm.stopPrank();

        for (uint i; i < addresses.length; ++i) {
            assertTrue(
                token.isBlacklisted(addresses[i]),
                "Address should be blacklisted"
            );
        }
    }

    /*  Test: Batch remove from blacklist with mixed status
        ├── Given: a batch of three addresses
        │   └── And: the first address is blacklisted
        │   └── And: the second and third addresses are not blacklisted
        ├── When: batch removing all addresses from blacklist
        │   └── Then: the operation should succeed
        │   └── Then: the blacklisted address should be removed
        │   └── Then: the non-blacklisted addresses should remain non-blacklisted
        └── When: checking each address status
            └── Then: isBlacklisted should return false for all addresses
    */
    function testBatchRemoveFromBlacklist_GivenSomeAddressesBlacklisted()
        public
    {
        address[] memory addresses = _generateAddresses(3);
        vm.startPrank(blacklistManager);
        token.addToBlacklist(addresses[0]);

        token.removeFromBlacklistBatched(addresses);
        vm.stopPrank();

        for (uint i; i < addresses.length; ++i) {
            assertFalse(
                token.isBlacklisted(addresses[i]),
                "Address should not be blacklisted"
            );
        }
    }

    /*  Test: Batch add to blacklist exceeding limit
        ├── Given: a batch of addresses exceeding the allowed limit
        └── When: attempting to add the batch to blacklist
            └── Then: it should revert with BatchLimitExceeded error
    */
    function testBatchAddToBlacklist_revertGivenBatchSizeExceedsLimit()
        public
    {
        address[] memory addresses = _generateAddresses(BATCH_LIMIT + 1);

        vm.prank(blacklistManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BatchLimitExceeded
                    .selector,
                BATCH_LIMIT + 1,
                BATCH_LIMIT
            )
        );
        token.addToBlacklistBatched(addresses);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Feature: Blacklist-Restricted Actions
    // Scenario: Restricting USP actions based on blacklist status
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /*  Test: Transfer between non-blacklisted addresses
        ├── Given: a sender with sufficient token balance
        │   └── And: neither sender nor recipient is blacklisted
        │   └── And: the transfer amount is within the sender's balance
        └── When: attempting to transfer tokens between the addresses
            └── Then: the transfer should complete successfully
            └── Then: the balances should be updated correctly
    */
    function testUpdate_GivenNeitherAddressBlacklisted(
        address user_,
        address user2_
    ) public {
        vm.assume(user_ != user2_);
        vm.assume(user_ != address(0) && user2_ != address(0));
        vm.assume(user_ != admin && user2_ != admin);
        vm.assume(user_ != blacklistManager && user2_ != blacklistManager);

        assertFalse(
            token.isBlacklisted(user_), "From address should not be blacklisted"
        );
        assertFalse(
            token.isBlacklisted(user2_), "To address should not be blacklisted"
        );

        // Mint some tokens to the user for transfer
        vm.prank(admin);
        token.mint(user_, 100);

        vm.prank(user_);
        token.exposed_update(user_, user2_, 100);
    }

    /*  Test: Transfer from blacklisted address
        ├── Given: the sender is blacklisted
        │   └── And: the recipient is not blacklisted
        └── When: attempting to transfer tokens
            └── Then: it should revert with BlacklistedAddress error
    */
    function testUpdate_revertGivenSenderIsBlacklisted(
        address user_,
        address user2_
    ) public {
        vm.assume(user_ != user2_);
        vm.assume(user_ != address(0) && user2_ != address(0));
        vm.assume(user_ != admin && user2_ != admin);
        vm.assume(user_ != blacklistManager && user2_ != blacklistManager);

        vm.prank(blacklistManager);
        token.addToBlacklist(user_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BlacklistedAddress
                    .selector,
                user_
            )
        );
        token.exposed_update(user_, user2_, 100);
    }

    /*  Test: Transfer to blacklisted address
        ├── Given: the recipient is blacklisted
        │   └── And: the sender is not blacklisted
        └── When: attempting to transfer tokens to the recipient
            └── Then: it should revert with BlacklistedAddress error
    */
    function testUpdate_revertGivenRecipientIsBlacklisted(
        address user_,
        address user2_
    ) public {
        vm.assume(user_ != user2_);
        vm.assume(user_ != address(0) && user2_ != address(0));
        vm.assume(user_ != admin && user2_ != admin);
        vm.assume(user_ != blacklistManager && user2_ != blacklistManager);

        vm.prank(blacklistManager);
        token.addToBlacklist(user2_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BlacklistedAddress
                    .selector,
                user2_
            )
        );
        token.exposed_update(user_, user2_, 100);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Helper functions
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    function _generateAddresses(uint count)
        internal
        returns (address[] memory)
    {
        address[] memory addresses = new address[](count);
        for (uint i; i < count; ++i) {
            addresses[i] = makeAddr(string.concat("user", vm.toString(i)));
        }
        return addresses;
    }
}
