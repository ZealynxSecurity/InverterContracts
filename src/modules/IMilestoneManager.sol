// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IMilestoneManager {
    //--------------------------------------------------------------------------
    // Types

    struct Milestone {
        /// @dev The duration of the milestone.
        ///      MUST not be zero.
        uint duration;
        /// @dev The budget for the milestone.
        ///      That is the number of tokens payed during the milestone's
        ///      duration.
        ///      CAN be zero.
        uint budget;
        /// @dev The timestamp the milestone started.
        uint startTimestamp;
        /// @dev Whether the milestone got submitted already.
        ///      Note that only accounts holding the {CONTRIBUTOR_ROLE()} can
        ///      submit milestones.
        bool submitted;
        /// @dev Whether the milestone is completed.
        ///      A milestone is completed if it got confirmed and started more
        ///      than duration seconds ago.
        bool completed;
        /// @dev The milestone's title.
        ///      MUST not be empty.
        string title;
        /// @dev The milestone's details.
        ///      MUST not be empty.
        string details;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by contributor.
    error Module__MilestoneManager__OnlyCallableByContributor();

    /// @notice Given title invalid.
    error Module__MilestoneManager__InvalidTitle();

    /// @notice Given duration invalid.
    error Module__MilestoneManager__InvalidDuration();

    /// @notice Given details invalid.
    error Module__MilestoneManager__InvalidDetails();

    /// @notice Given milestone id invalid.
    error Module__MilestoneManager__InvalidMilestoneId();

    /// @notice Given milestone not updateable.
    error Module__MilestoneManager__MilestoneNotUpdateable();

    /// @notice Given milestone not removable.
    error Module__MilestoneManager__MilestoneNotRemovable();

    /// @notice Given milestone not submitable.
    error Module__MilestoneManager__MilestoneNotSubmitable();

    /// @notice Given milestone not confirmable.
    error Module__MilestoneManager__MilestoneNotConfirmable();

    /// @notice Given milestone not declineable.
    error Module__MilestoneManager__MilestoneNotDeclineable();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event MilestoneAdded(
        uint indexed id,
        uint duration,
        uint budget,
        string title,
        string details
    );

    /// @notice Event emitted when a milestone got updated.
    event MilestoneUpdated(
        uint indexed id, uint duration, uint budget, string details
    );

    /// @notice Event emitted when a milestone removed.
    event MilestoneRemoved(uint indexed id);

    /// @notice Event emitted when a milestone submitted.
    event MilestoneSubmitted(uint indexed id);

    /// @notice Event emitted when a milestone confirmed.
    event MilestoneConfirmed(uint indexed id);

    /// @notice Event emitted when a milestone declined.
    event MilestoneDeclined(uint indexed id);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Milestone View Functions

    /// @notice Returns the milestone with id `id`.
    /// @dev Returns empty milestone in case id `id` is invalid.
    /// @param id The id of the milstone to return.
    /// @return Milestone with id `id`.
    function getMilestone(uint id) external view returns (Milestone memory);

    //----------------------------------
    // Milestone Mutating Functions

    /// @notice Adds a new milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param title The title for the new milestone.
    /// @param startDate The starting date of the new milestone.
    /// @param details The details of the new milestone.
    /// @return The newly added milestone's id.
    function addMilestone(
        string memory title,
        uint startDate,
        string memory details
    ) external returns (uint);

    /// @notice Changes a milestone's details.
    /// @dev Only callable by authorized addresses.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    /// @param details The new details of the milestone.
    function updateMilestoneDetails(uint id, string memory details) external;

    /// @notice Changes a milestone's starting date.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid or milestone already removed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    /// @param startDate The new starting date of the milestone.
    function updateMilestoneStartDate(uint id, uint startDate) external;

    /// @notice Removes a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid or milestone already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function removeMilestone(uint id) external;

    /// @notice Submits a milestone.
    /// @dev Only callable by addresses holding the contributor role.
    /// @dev Reverts if id invalid or milestone already removed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function submitMilestone(uint id) external;

    // @todo mp, felix: Should be renamed to `completeMilestone()`?

    /// @notice Confirms a submitted milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone already removed, or milestone not
    ///      yet submitted.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function confirmMilestone(uint id) external;

    /// @notice Declines a submitted milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone already removed, milestone not
    ///      yet submitted, or milestone already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function declineMilestone(uint id) external;
}
