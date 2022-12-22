# SingleVoteGovernance.sol
File: [SingleVoteGovernance.sol](../../src/modules/governance/SingleVoteGovernor.sol)

## Things to know

1. This contract implements a single vote governance module.
2. This contract keeps a list of authorized addresses and these addresses can create `Votes` wich other addresses can support or reject.
3. Votes are open for a set length of time. If they don't reach quorum at time of voting, they won't be able to be executed later, even if the quorum is lowered.
4. Each address can vote only once. Votes can not be modified.
5. The stored action can only be executed after the voting period ends, even if quorum was reached earlier.

## Modifier(s)

### 1. onlySelf

This modifier ensures that the `msg.sender` is the same as the `SingleVoteGovernor` contract (`address(this)`).

### 2. onlyVoter

This modifier ensures that the `msg.sender` is an authorised voter (member of the mapping `isVoter`).

## View Function(s)

### 1. isAuthorized

`function isAuthorized(address who) public view returns (bool);`

This function checks whether the address `who` is authorized or not.

#### Parameter(s)

1. `address who` -> The address whose authorization you want to check.

#### Return Data

1. `bool` -> True if address `who` is `authorized()`, false otherwise.

> NOTE: The governance contract (`SingleVoteGovernance.sol`) itself is only authorized.

### 2. getReceipt

`function getReceipt(uint _ID, address voter) public view returns (Receipt memory);`

This function helps to fetch the `Receipt` (see `NOTE 1` below) of a `Motion`(see `NOTE 2` below) with id of `_ID` and associated with the address `voter`.

> NOTE 1: `Receipt` is the a struct containing `bool hasVoted` and `uint8 support`.

> NOTE 2: `Motion` is a struct with the following structure:

```
struct Motion {
        // Execution data.
        address target;
        bytes action;
        // Governance data.
        uint startTimestamp;
        uint endTimestamp;
        uint requiredQuorum;
        // Voting result.
        uint forVotes;
        uint againstVotes;
        uint abstainVotes;
        mapping(address => Receipt) receipts;
        // Execution result.
        uint executedAt;
        bool executionResult;
        bytes executionReturnData;
    }
```

#### Parameter(s)

1. `uint \_ID` -> The identifying number of the `Motion` for which you want to see the `Receipt`.
2. `address voter` -> Given the `_ID` of the `Motion`, the address of the voter for which you want to see the `Receipt`.

#### Return Data

1. Receipt -> A `Receipt` of the address `voter` from the `Motion` with id `_ID`.

### 3. MAX_DURATION_DURATION

`function MAX_VOTING_DURATION() external view returns (uint);`

#### Return Data

1. `uint` -> The maximum duration for voting, which is currently hardcoded to `2 weeks`.

### 4. MIN_VOTING_DURATION

`function MIN_VOTING_DURATION() external view returns (uint);`

#### Return Data

1. `uint` -> The minimum duration for voting, which is currently hardcoded to `1 days`.

## Write Function(s)

### 1. initialize

`function initialize(IProposal proposal, uint8 _startingQuorum, uint _voteDuration, Metadata memory metadata) external`

This function initializes the module and then sets the `quorum`, list of voters and `voteDuration`.

#### Parameters

1. `IProposal proposal` -> The module's proposal instance.
2. `Metadata metadata` -> The module's metadata.
3. `bytes configData` -> Encrypted data which contains list of voters, the required quorum, and the voting duration.

### 2. setQuorum

`function setQuorum(uint newQuorum) external;`

This function can only be called by the `SingleVoteGovernance` contract and it sets/updates the `quorum` of the proposal.

#### Parameter(s)

1. `uint newQuorum` -> The new value of the `quorum`.

> NOTE: 0 is a valid quorum value

### 3. setVotingDuration

`function setVotingDuration(uint newVoteDuration) external;`

This function can only be called by the `SingleVoteGovernance` contract and it sets/updates the `voteDuration` of the proposal.

#### Parameter(s)

1. `uint newVoteDuration` -> The new `voteDuration`.

> NOTE: The `newVoteDuration` must be between the `MIN_VOTING_DURATION` and `MAX_VOTING_DURATION`.

### 4. addVoter

`function addVoter(address who) external;`

This function is used to add address `who` as a voter in case they are not already added as a voter.

#### Parameter(s)

1. `address who` -> The address of the voter to add to the voting list.

### 5. removeVoter

`function removeVoter(address who) external;`

Callable only by the `SingleVoteGovernance` contract and used to remove the address `who` as a valid voter. This will revert in case address `who` is the last voter or if removing `who` will lead to the `quorum` never being reached.

#### Parameter(s)

1. `address who` -> The address of the voter to remove from the voting list.

### 6. transferVotingRights

`function transferVotingRights(address to) external;`

This function can only be called by a valid voter and used to transfer the voting rights of the `msg.sender` to address `to`. Also, this function would revert if the address `to` is already a voter.

#### Parameter(s)

1. `address to` -> The address to whom you want to transfer your voting rights to.

> NOTE: You cannot transfer your voting rights to `address(0)`

### 7. createMotion

`function createMotion(address target, bytes calldata action) external returns (uint);`

This function is used to create a new `Motion` with the given `target` address and the given `action` bytes. This function is callable only by a valid voter and returns the ID of the newly created `Motion`.

#### Parameter(s)

1. `address target` -> The target address for creating the new `Motion`.
2. `bytes action` -> The action bytes for creating the new `Motion`.

#### Return Data

1. `uint` -> ID of the new `Motion` that was created.

### 8. castVote

`function castVote(uint motionId, uint8 support) external;`

This function is used to cast vote (support) to a `Motion` with ID `motionId`. The function revert if `support` is invalid. Otherwise,
`0 == for`
`1 == against`
`2 == abstain`

#### Parameter(s)

1. `uint motionId` -> The ID of the `Motion` where you want to cast vote
2. `uint8 support` -> Vote in support, against or abstain.

### 9. executeMotion

`function executeMotion(uint motionId) external;`

This function is used to execute the `Motion` with id of `motionId`. This function will revert if `motionId` is invalid or voting duration has passed or if the motion has already been executed or the necessary quorum was not reached.

#### Parameter(s)

1. `uint motionId` -> The ID of the `Motion` to execute