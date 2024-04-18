// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IGovernor {
    //--------------------------------------------------------------------------
    // Structs

    /// @dev The timelock is needed to upgrade a beacon to new implementation.
    struct Timelock {
        /// @dev Is the timelock currently active
        bool timelockActive;
        /// @dev Timestamp that represents from when the upgrade can be carried out
        uint timelockUntil;
        /// @dev The new inteded Implementation address of the beacon
        address intendedImplementation;
        /// @dev The new intended minor Version of the beacon
        uint intendedMinorVersion;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The given address is invalid
    error Governor__InvalidAddress(address adr);

    /// @notice The given amount is invalid
    error Governor__InvalidTimelockPeriod(uint amt);

    /// @notice The given target address is not accessible
    error Governor__BeaconNotAccessible(address target);

    /// @notice This function can only be accessed by the CommunityMultisig or TeamMultisig
    error Governor__OnlyCommunityOrTeamMultisig();

    /// @notice The timelock period needed for the beacon to be upgraded has not been exceeded yet
    error Governor__TimelockPeriodNotExceeded();

    /// @notice This Upgrade process for this beacon has not yet been started
    error Governor__UpgradeProcessNotStarted();

    /// @notice The call to the target contract has failed
    error Governor__CallToTargetContractFailed();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new timelock period for a upgrade of a beacon is started
    /// @param beacon The address of the beacon
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    /// @param timelockExceeded Timestamp of when the timelock is exceeded
    event BeaconTimelockStarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint timelockExceeded
    );

    /// @notice Event emitted when a beacon is upgraded
    /// @param beacon The address of the beacon
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    event BeaconUpgraded(
        address beacon, address newImplementation, uint newMinorVersion
    );

    /// @notice Event emitted when a beacon upgraded is canceled
    /// @param beacon The address of the beacon
    event BeaconUpgradedCanceled(address beacon);

    /// @notice Event emitted when a timelock period is set
    /// @param newTimelockPeriod The new timelock period
    event TimelockPeriodSet(uint newTimelockPeriod);

    /// @notice Event emitted when a beacon shutdown is initiated
    /// @param beacon The address of the beacon
    event BeaconShutdownInitiated(address beacon);

    /// @notice Event emitted when a beacon is forcefully upgraded and the implementation gets restarted immediatly
    /// @param beacon The address of the beacon
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    event BeaconForcefullyUpgradedAndImplementationRestarted(
        address beacon, address newImplementation, uint newMinorVersion
    );

    /// @notice Event emitted when a beacon implementation is restarted
    /// @param beacon The address of the beacon
    event BeaconImplementationRestarted(address beacon);

    /// @notice Event emitted when a the governor contract accepts the ownership over another contract
    /// @param adr The address of the contract that distributed the ownership
    event OwnershipAccepted(address adr);

    //--------------------------------------------------------------------------
    // Initialization

    function init(
        address communityMultisig,
        address teamMultisig,
        uint timelockPeriod //@note should we add taxMan here?
    ) external;

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns the current timelock of a beacon address
    /// @param beacon The address of the beacon
    /// @return The timelock of the beacon address
    function getBeaconTimelock(address beacon)
        external
        returns (Timelock memory);

    //--------------------------------------------------------------------------
    // TaxMan

    /// @notice Returns the TaxMan address
    /// @return Address of the TaxMan
    function getTaxMan() external view returns (address);

    /// @notice Sets the address of the TaxMan
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE
    /// @param newTaxMan The address of the new TaxMan
    function setTaxMan(address newTaxMan) external;

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    //Upgrade

    /// @notice Starts the upgrade process of a beacon by creating a timelock period after which the beacon can be upgraded via triggerUpgradeBeaconWithTimelock()
    //@dev This function will override previous timelocks even if they are active
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE
    /// @param beacon The address of the beacon that is intended to be upgraded
    /// @param newImplementation The address of the intended new Implementation of the beacon.
    /// @param newMinorVersion The intended new minor version of the beacon.
    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external;

    /// @notice Upgrades a beacon with the data provided by the active timelock
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE
    /// @param beacon The address of the beacon that is intended to be upgraded
    function triggerUpgradeBeaconWithTimelock(address beacon) external;

    /// @notice Cancels a Upgrade of beacon by setting the active timelock to inactive
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE
    /// @param beacon The address of the beacon for which the timelock should be canceled
    function cancelUpgrade(address beacon) external;

    /// @notice Sets the timelock period of a beacon upgrade process
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE
    /// @param newtimelockPeriod The new timelock period
    function setTimelockPeriod(uint newtimelockPeriod) external;

    //---------------------------
    //Emergency Shutdown

    /// @notice Initiates the shutdown of a beacon
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE
    /// @param beacon The address of the beacon that should be shut down
    function initiateBeaconShutdown(address beacon) external;

    /// @notice This function forces the upgrade of a beacon and restarts the implementation afterwards
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE
    /// @param beacon The address of the beacon that is intended to be upgraded and restarted
    /// @param newImplementation The address of the intended new Implementation of the beacon.
    /// @param newMinorVersion The intended new minor version of the beacon.
    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external;

    /// @notice Restarts the beacon implementation
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE
    /// @param beacon The address of the beacon that should restarted
    function restartBeaconImplementation(address beacon) external;

    //---------------------------
    //Ownable2Step

    /// @notice Accepts the ownership over the target address
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE
    /// @param adr The address of target that wants to hand over the ownership
    function acceptOwnership(address adr) external;
}
