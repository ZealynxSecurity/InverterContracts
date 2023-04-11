// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    FundingManagerMock,
    IFundingManager
} from "test/utils/mocks/proposal/base/FundingManagerMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract FundingManagerTest is Test {
    // SuT
    FundingManagerMock fundingManager;

    // Mocks
    ERC20Mock underlier;

    /// The maximum supply of underlying tokens. We keep it one factor below the MAX_SUPPLY of the rebasing token.
    /// Note that this sets the deposit limit for the fundign manager.
    uint internal constant MAX_SUPPLY = 100_000_000e18;

    // Other constants.
    uint8 private constant DECIMALS = 18;
    uint private constant PROPOSAL_ID = 1;

    function setUp() public {
        vm.warp(1_680_220_800); // March 31, 2023 at 00:00 GMT
        underlier = new ERC20Mock("Mock", "MOCK");

        fundingManager = new FundingManagerMock();
        fundingManager.init(underlier, PROPOSAL_ID, DECIMALS);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        assertEq(fundingManager.decimals(), DECIMALS);
        assertEq(
            fundingManager.name(),
            "elastic Inverter Funding Token - Proposal #1"
        );
        assertEq(fundingManager.symbol(), "eIFT-1");

        assertEq(fundingManager.totalSupply(), 0);
        assertEq(fundingManager.scaledTotalSupply(), 0);
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        fundingManager.init(underlier, PROPOSAL_ID, DECIMALS);
    }

    function testInitFailsForNonInitializerFunction() public {
        fundingManager = new FundingManagerMock();

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        fundingManager.initNoInitializer(underlier, PROPOSAL_ID, DECIMALS);
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    function testDeposit(address user, uint amount) public {
        vm.assume(user != address(0) && user != address(fundingManager));
        vm.assume(amount > 1 && amount <= MAX_SUPPLY);

        // Mint tokens to depositor.
        underlier.mint(user, amount);

        // User deposits tokens.
        vm.startPrank(user);
        {
            underlier.approve(address(fundingManager), type(uint).max);
            fundingManager.deposit(amount);
        }
        vm.stopPrank();

        // User received funding tokens on 1:1 basis.
        assertEq(fundingManager.balanceOf(user), amount);
        // FundingManager fetched tokens from the user.
        assertEq(underlier.balanceOf(address(fundingManager)), amount);

        // Simulate spending from the FundingManager by burning tokens.
        uint expenses = amount / 2;
        underlier.burn(address(fundingManager), expenses);

        // Rebase manually. Rebase is executed automatically on every token
        // balance mutating function.
        fundingManager.rebase();

        // User has half the token balance as before.
        assertEq(fundingManager.balanceOf(user), amount - expenses);
    }

    function testSelfDepositFails() public {
        // User deposits tokens.
        vm.prank(address(fundingManager));
        vm.expectRevert(
            IFundingManager.Proposal__FundingManager__CannotSelfDeposit.selector
        );
        fundingManager.deposit(1);
    }

    struct UserDeposits {
        address[] users;
        uint[] deposits;
    }

    mapping(address => bool) _usersCache;

    UserDeposits userDeposits;

    function generateValidUserDeposits(
        uint amountOfDepositors,
        uint[] memory depositAmounts
    ) public returns (UserDeposits memory) {
        // We cap the amount each user will deposit so we dont exceed the total supply.
        uint maxDeposit = (MAX_SUPPLY / amountOfDepositors);
        for (uint i = 0; i < amountOfDepositors; i++) {
            //we generate a "random" address
            address addr = address(uint160(i + 1));
            if (
                addr != address(0) && addr != address(fundingManager)
                    && !_usersCache[addr] && addr != address(this)
            ) {
                //This should be enough for the case we generated a duplicate address
                addr = address(uint160(block.timestamp - i));
            }

            // Store the address and mark it as used.
            userDeposits.users.push(addr);
            _usersCache[addr] = true;

            //This is to avoid the fuzzer to generate a deposit amount that is too big
            depositAmounts[i] = bound(depositAmounts[i], 1, maxDeposit - 1);
            userDeposits.deposits.push(depositAmounts[i]);
        }
        return userDeposits;
    }

    function testDepositAndSpendFunds(
        uint userAmount,
        uint[] calldata depositAmounts
    ) public {
        userAmount = bound(userAmount, 2, 999);
        vm.assume(userAmount <= depositAmounts.length);

        UserDeposits memory input =
            generateValidUserDeposits(userAmount, depositAmounts);

        // Mint deposit amount of underliers to users.
        for (uint i; i < input.users.length; ++i) {
            underlier.mint(input.users[i], input.deposits[i]);
        }

        // Each user gives infinite allowance to fundingManager.
        for (uint i; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            underlier.approve(address(fundingManager), type(uint).max);
        }

        // Half the users deposit their underliers.
        uint undelierDeposited = 0; // keeps track of amount deposited so we can use it later
        for (uint i; i < (input.users.length / 2); ++i) {
            vm.prank(input.users[i]);
            fundingManager.deposit(input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
            assertEq(underlier.balanceOf(input.users[i]), 0);

            assertEq(
                underlier.balanceOf(address(fundingManager)),
                undelierDeposited + input.deposits[i]
            );
            undelierDeposited += input.deposits[i];
        }

        // A big amount of underlier tokens leave the manager, f.ex at Milestone start.
        uint expenses = undelierDeposited / 2;
        underlier.burn(address(fundingManager), expenses);

        // Confirm that the users who funded tokens, lost half their receipt tokens.
        // Note to rebase because balanceOf is not a token-state mutating function.
        fundingManager.rebase();
        for (uint i; i < input.users.length / 2; ++i) {
            // Note that we can be off-by-one due to rounding.
            assertApproxEqAbs(
                fundingManager.balanceOf(input.users[i]),
                input.deposits[i] / 2,
                1
            );
        }

        // The other half of the users deposit their underliers.
        for (uint i = input.users.length / 2; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            fundingManager.depositFor(input.users[i], input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }
    }

    function testDepositSpendUntilEmptyRedepositAndWindDown(
        uint userAmount,
        uint[] calldata depositAmounts
    ) public {
        userAmount = bound(userAmount, 1, 999);
        vm.assume(userAmount <= depositAmounts.length);

        UserDeposits memory input =
            generateValidUserDeposits(userAmount, depositAmounts);

        // ----------- SETUP ---------

        //Buffer variable to track how much underlying balance each user has left
        uint[] memory remainingFunds = new uint[](input.users.length);

        //the deployer deposits 1 token so the proposal is never empty
        underlier.mint(address(this), 1);
        vm.startPrank(address(this));
        underlier.approve(address(fundingManager), type(uint).max);
        fundingManager.deposit(1);
        vm.stopPrank();
        assertEq(fundingManager.balanceOf(address(this)), 1);

        // Mint deposit amount of underliers to users.
        for (uint i; i < input.users.length; ++i) {
            underlier.mint(input.users[i], input.deposits[i]);
            remainingFunds[i] = input.deposits[i];
        }

        // Each user gives infinite allowance to fundingManager.
        for (uint i; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            underlier.approve(address(fundingManager), type(uint).max);
        }

        // ---- STEP ONE: FIRST MILESTONE

        // Half the users deposit their underliers.
        for (uint i; i < input.users.length / 2; ++i) {
            vm.prank(input.users[i]);
            fundingManager.deposit(input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }

        // The fundingManager spends an amount of underliers.
        uint expenses = fundingManager.totalSupply() / 2;
        underlier.burn(address(fundingManager), expenses);

        // The users who funded tokens, lost half their receipt tokens.
        // Note to rebase because balanceOf is not a token-state mutating function.
        fundingManager.rebase();
        for (uint i; i < input.users.length / 2; ++i) {
            // Note that we can be off-by-one due to rounding.
            assertApproxEqAbs(
                fundingManager.balanceOf(input.users[i]),
                remainingFunds[i] / 2,
                1
            );
            //We also update the balance tracking
            remainingFunds[i] = fundingManager.balanceOf(input.users[i]);
        }

        // ---- STEP TWO: SECOND MILESTONE

        // The other half of the users deposit their underliers.
        for (uint i = input.users.length / 2; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            fundingManager.depositFor(input.users[i], input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }

        // The fundingManager spends an amount of underliers.
        expenses = fundingManager.totalSupply() / 2;
        underlier.burn(address(fundingManager), expenses);

        // Everybody who deposited lost half their corresponding receipt tokens.
        // Note to rebase because balanceOf is not a token-state mutating function.
        fundingManager.rebase();
        for (uint i; i < input.users.length; ++i) {
            // Note that we can be off-by-one due to rounding.
            assertApproxEqAbs(
                fundingManager.balanceOf(input.users[i]),
                remainingFunds[i] / 2,
                1
            );

            //We also update the balance tracking
            remainingFunds[i] = fundingManager.balanceOf(input.users[i]);
        }

        // ---- STEP THREE: WIND DOWN PROPOSAL

        // The proposal is deemed completed, so everybody withdraws
        for (uint i; i < input.users.length; ++i) {
            uint balance = fundingManager.balanceOf(input.users[i]);
            if (balance != 0) {
                vm.prank(input.users[i]);
                //to test both withdraw and withdrawTo
                if (i % 2 == 0) {
                    fundingManager.withdraw(balance);
                } else {
                    fundingManager.withdrawTo(input.users[i], balance);
                }
            }
        }

        //Once everybody has withdrawn, only the initial token + some possible balance rounding leftovers remain.
        assertTrue(fundingManager.totalSupply() <= (1 + input.users.length));

        // ---- STEP FOUR: RE-START PROPOSAL

        // Some time passes, and now half the users deposit their underliers again to continue funding (if they had any funds left).
        for (uint i; i < input.users.length / 2; ++i) {
            if (remainingFunds[i] != 0) {
                vm.prank(input.users[i]);
                fundingManager.deposit(remainingFunds[i]);

                assertEq(
                    fundingManager.balanceOf(input.users[i]), remainingFunds[i]
                );
            }
        }
    }
}
