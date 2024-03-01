// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

import {IKPIRewarder} from "./IKPIRewarder.sol";

import {
    IStakingManager,
    StakingManager,
    SafeERC20,
    IERC20,
    IERC20PaymentClient,
    ReentrancyGuard
} from "./StakingManager.sol";

import {
    IOptimisticOracleIntegrator,
    OptimisticOracleIntegrator,
    OptimisticOracleV3CallbackRecipientInterface,
    OptimisticOracleV3Interface,
    ClaimData
} from "./oracle/OptimisticOracleIntegrator.sol";

contract KPIRewarder is
    IKPIRewarder,
    StakingManager,
    OptimisticOracleIntegrator
{
    using SafeERC20 for IERC20;

    // =================================================================
    // General Information about the working of this contract
    // This module enable KPI based reward distribution into the staking manager by using UMAs Optimistic Oracle.

    // It works in the following way:
    // - The owner can create KPIs, which are a set of tranches with rewards assigned. These can be continuous or not (see below)
    // - An external actor with the ASSERTER role can trigger the posting of an assertion to the UMA Oracle, specifying the value to be asserted and the KPI to use for the reward distrbution in case it resolves
    // - To ensure fairness, all new staking requests are queued until the next KPI assertion is resolved. They will be added before posting the next assertion.
    // - Once the assertion resolves, the UMA oracle triggers the assertionResolvedCallback() function. This will calculate the final reward value and distribute it to the stakers.

    // =================================================================

    // KPI and Configuration Storage
    uint public KPICounter;
    mapping(uint => KPI) public registryOfKPIs;
    mapping(bytes32 => RewardRoundConfiguration) public assertionConfig;

    // Deposit Queue
    address[] public stakingQueue;
    mapping(address => uint) public stakingQueueAmounts;
    uint public totalQueuedFunds;
    uint public constant MAX_QUEUE_LENGTH = 50;

    /*
    Tranche Example:
    trancheValues = [10000, 20000, 30000]
    trancheRewards = [100, 200, 100]
    continuous = false
     ->   if KPI is 12345, reward is 100 for the tranche [0-10000]
     ->   if KPI is 32198, reward is 400 for the tranches [0-10000, 10000-20000 and 20000-30000]

    if continuous = true
    ->    if KPI is 15000, reward is 200 for the tranches [100% 0-10000, 50% * 10000-15000]
    ->    if KPI is 25000, reward is 350 for the tranches [100% 0-10000, 100% 10000-20000, 50% 20000-30000]

    */

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    )
        external
        virtual
        override(StakingManager, OptimisticOracleIntegrator)
        initializer
    {
        __Module_init(orchestrator_, metadata);

        (address stakingTokenAddr, address currencyAddr, address ooAddr) =
            abi.decode(configData, (address, address, address));

        _setStakingToken(stakingTokenAddr);

        // TODO ERC165 Interface Validation for the OO, for now it just reverts
        oo = OptimisticOracleV3Interface(ooAddr);
        defaultIdentifier = oo.defaultIdentifier();

        setDefaultCurrency(currencyAddr);
        setOptimisticOracle(ooAddr);
    }

    // ======================================================================
    // View functions

    /// @inheritdoc IKPIRewarder
    function getKPI(uint KPInum) public view returns (KPI memory) {
        return registryOfKPIs[KPInum];
    }

    /// @inheritdoc IKPIRewarder
    function getAssertionConfig(bytes32 assertionId)
        public
        view
        returns (RewardRoundConfiguration memory)
    {
        return assertionConfig[assertionId];
    }

    /// @inheritdoc IKPIRewarder
    function getStakingQueue() public view returns (address[] memory) {
        return stakingQueue;
    }

    // ========================================================================
    // Assertion Manager functions:

    /// @inheritdoc IKPIRewarder
    /// @dev about the asserter address: any address can be set as asserter, it will be expected to pay for the bond on posting.
    /// The bond tokens can also be deposited in the Module and used to pay for itself, but ONLY if the bond token is different from the one being used for staking.
    /// If the asserter is set to 0, whomever calls postAssertion will be paying the bond.
    function postAssertion(
        bytes32 dataId,
        bytes32 data,
        address asserter,
        uint assertedValue,
        uint targetKPI
    ) public onlyModuleRole(ASSERTER_ROLE) returns (bytes32 assertionId) {
        // =====================================================================
        // Input Validation

        //  If the asserter is the Module itself, we need to ensure the token paid for bond is different than the one used for staking, since it could mess with the balances
        if (
            asserter == address(this)
                && address(defaultCurrency) == stakingToken
        ) {
            revert Module__KPIRewarder__ModuleCannotUseStakingTokenAsBond();
        }

        // Make sure that we are targeting an existing KPI
        if (KPICounter == 0 || targetKPI >= KPICounter) {
            revert Module__KPIRewarder__InvalidKPINumber();
        }

        // Question: what kind of checks should or can we implement on the data side?
        // Technically the value mentioned inside "data" (and posted publicly) wouldn't need to be the same as assertedValue...

        // =====================================================================
        // Staking Queue Management

        for (uint i = 0; i < stakingQueue.length; i++) {
            address user = stakingQueue[i];
            _stake(user, stakingQueueAmounts[user]);
            totalQueuedFunds -= stakingQueueAmounts[user];
            stakingQueueAmounts[user] = 0;
        }

        delete stakingQueue; // reset the queue

        // =====================================================================
        // Assertion Posting

        assertionId = assertDataFor(dataId, data, asserter);
        assertionConfig[assertionId] = RewardRoundConfiguration(
            block.timestamp, assertedValue, targetKPI, false
        );

        // (return assertionId)
    }

    // ========================================================================
    // Owner Configuration Functions:

    // Top up funds to pay the optimistic oracle fee
    /// @inheritdoc IKPIRewarder
    function depositFeeFunds(uint amount)
        external
        onlyOrchestratorOwner
        nonReentrant
        validAmount(amount)
    {
        defaultCurrency.safeTransferFrom(_msgSender(), address(this), amount);

        emit FeeFundsDeposited(address(defaultCurrency), amount);
    }

    /// @inheritdoc IKPIRewarder
    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external onlyOrchestratorOwner returns (uint) {
        uint _numOfTranches = _trancheValues.length;

        if (_numOfTranches < 1 || _numOfTranches > 20) {
            revert Module__KPIRewarder__InvalidTrancheNumber();
        }

        if (_numOfTranches != _trancheRewards.length) {
            revert Module__KPIRewarder__InvalidKPIValueLengths();
        }

        uint _totalKPIRewards = _trancheRewards[0];
        if (_numOfTranches > 1) {
            for (uint i = 1; i < _numOfTranches; i++) {
                if (_trancheValues[i - 1] >= _trancheValues[i]) {
                    revert Module__KPIRewarder__InvalidKPITrancheValues();
                }

                _totalKPIRewards += _trancheRewards[i];
            }
        }

        uint KpiNum = KPICounter;

        registryOfKPIs[KpiNum] = KPI(
            _numOfTranches,
            _totalKPIRewards,
            _continuous,
            _trancheValues,
            _trancheRewards
        );
        KPICounter++;

        emit KPICreated(
            KpiNum,
            _numOfTranches,
            _totalKPIRewards,
            _continuous,
            _trancheValues,
            _trancheRewards
        );

        return (KpiNum);
    }

    // ===========================================================
    // New user facing functions (stake() is a StakingManager override) :

    /// @inheritdoc IStakingManager
    function stake(uint amount)
        external
        override
        nonReentrant
        validAmount(amount)
    {
        if (stakingQueue.length >= MAX_QUEUE_LENGTH) {
            revert Module__KPIRewarder__StakingQueueIsFull();
        }

        address sender = _msgSender();

        if (stakingQueueAmounts[sender] == 0) {
            // new stake for queue
            stakingQueue.push(sender);
        }
        stakingQueueAmounts[sender] += amount;
        totalQueuedFunds += amount;

        //transfer funds to stakingManager
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);

        emit StakeEnqueued(sender, amount);
    }

    /// @inheritdoc IKPIRewarder
    function dequeueStake() public nonReentrant {
        address user = _msgSender();

        // keep it idempotent
        if (stakingQueueAmounts[user] != 0) {
            uint amount = stakingQueueAmounts[user];

            stakingQueueAmounts[user] = 0;
            totalQueuedFunds -= amount;

            for (uint i; i < stakingQueue.length; i++) {
                if (stakingQueue[i] == user) {
                    stakingQueue[i] = stakingQueue[stakingQueue.length - 1];
                    stakingQueue.pop();
                    break;
                }
            }

            emit StakeDequeued(user, amount);

            //return funds to user
            IERC20(stakingToken).safeTransfer(user, amount);
        }
    }

    // ============================================================
    // Optimistic Oracle Overrides:

    /// @inheritdoc IOptimisticOracleIntegrator
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public override {
        if (_msgSender() != address(oo)) {
            revert Module__OptimisticOracleIntegrator__CallerNotOO();
        }

        if (assertedTruthfully) {
            // SECURITY NOTE: this will add the value, but provides no guarantee that the fundingmanager actually holds those funds.

            // Calculate rewardamount from assertionId value
            KPI memory resolvedKPI =
                registryOfKPIs[assertionConfig[assertionId].KpiToUse];
            uint rewardAmount;

            for (uint i; i < resolvedKPI.numOfTranches; i++) {
                if (
                    resolvedKPI.trancheValues[i]
                        <= assertionConfig[assertionId].assertedValue
                ) {
                    //the asserted value is above tranche end
                    rewardAmount += resolvedKPI.trancheRewards[i];
                } else {
                    //tranche was not completed
                    if (resolvedKPI.continuous) {
                        //continuous distribution
                        uint trancheRewardValue = resolvedKPI.trancheRewards[i];
                        uint trancheStart =
                            i == 0 ? 0 : resolvedKPI.trancheValues[i - 1];

                        uint achievedReward = assertionConfig[assertionId]
                            .assertedValue - trancheStart;
                        uint trancheEnd =
                            resolvedKPI.trancheValues[i] - trancheStart;

                        rewardAmount +=
                            achievedReward * (trancheRewardValue / trancheEnd); // since the trancheRewardValue will be a very big number.
                    }
                    //else -> no reward

                    //exit the loop
                    break;
                }
            }

            _setRewards(rewardAmount, 1);
        }
        emit DataAssertionResolved(
            assertedTruthfully,
            assertionData[assertionId].dataId,
            assertionData[assertionId].data,
            assertionData[assertionId].asserter,
            assertionId
        );
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public override {
        //Do nothing
    }
}
