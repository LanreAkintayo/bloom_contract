// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VRFV2WrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import {DisputeStorage} from "./DisputeStorage.sol";

import {DisputeManager} from "./DisputeManager.sol";
import {TypesLib} from "../../library/TypesLib.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

import {console} from "forge-std/Test.sol";

contract JurorManager is VRFV2WrapperConsumerBase, ConfirmedOwner, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    DisputeStorage public ds;

    IERC20 public bloomToken;
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint256 public constant MAX_PERCENT = 10_000; // This represents 100%

    enum RequestType {
        INITIAL,
        TIE_BREAKER
    }

    // For randomness;
    mapping(uint256 => TypesLib.RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => address[]) private activeExperiencedByDispute;
    mapping(uint256 => address[]) private activeNewbiesByDispute;
    mapping(uint256 => uint256) private experienceNeededByDispute;
    mapping(uint256 => uint256) private newbieNeededByDispute;
    mapping(uint256 => uint256) private requestIdToDispute;
    mapping(uint256 => uint256) private numOfJurors;
    mapping(uint256 => mapping(address => uint256)) private selectionScoresTemp;
    mapping(uint256 => RequestType) private requestToType;
    mapping(uint256 => address[]) private poolToPickFrom;

    mapping(uint256 disputeId => address) private tieBreakerJuror;

    uint256 public tieBreakingDuration = 1 days;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error JurorManager__ZeroAddress();
    error JurorManager__ZeroAmount();
    error JurorManager__InvalidStakeAmount();
    error JurorManager__AlreadyRegistered();
    error JurorManager__NotRegistered();
    error JurorManager__AlreadyAssignedJurors();
    error JurorManager__ThresholdMismatched();
    error JurorManager__RequestNotFound();
    error JurorManager__NotEligible();
    error JurorManager__AlreadyVoted();
    error JurorManager__MaxVoteExceeded();
    error JurorManager__NotFinished();
    error JurorManager__DisputeNotEnded();
    error JurorManager__NotInVotingPeriod();
    error JurorManager__VotingPeriodExpired();
    error JurorManager__NotInStandardVotingPeriod();
    error JurorManager__MaxAppealExceeded();
    error JurorManager__AlreadyWinner();
    error JurorManager__MustVote();
    error JurorManager__NotEnoughStakeToWithdraw();
    error JurorManager__WithdrawalCooldownNotOver();
    error JurorManager__InsufficientExperienced();
    error JurorManager__InsufficientNewbies();
    error JurorManager__InsufficientJurors();
    error JurorManager__VotingNotFinished();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event JurorRegistered(address indexed juror, uint256 stakeAmount);
    event MinStakeAmountUpdated(uint256 indexed newMinStakeAmount);
    event MaxStakeAmountUpdated(uint256 indexed newMaxStakeAmount);
    event MoreStaked(address indexed juror, uint256 indexed additionalStaked, uint256 indexed newStakeAmount);
    event JurorsSelected(uint256 indexed disputeId, address[] indexed selected);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);
    event Voted(uint256 indexed disputeId, address indexed jurorAddress, address indexed support);
    event JurorAdded(uint256 indexed _disputeId, address[] indexed newJurors);
    event StandardVotingDurationExtended(uint256 indexed _disputeId, uint256 indexed _extendDuration);
    event StakeWithdrawn(address indexed jurorAddress, uint256 indexed amount);
    event TieSelectionCompleted(uint256 indexed _disputeId, address indexedselectedJurorAddress);
    event ExtendedVotingPeriod(uint256 indexed _disputeId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _storageAddress, address _linkAddress, address _wrapperAddress)
        VRFV2WrapperConsumerBase(_linkAddress, _wrapperAddress)
        ConfirmedOwner(msg.sender)
    {
        ds = DisputeStorage(_storageAddress);
        bloomToken = ds.getBloomToken();
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    function registerJuror(uint256 stakeAmount) external {
        // Load juror data once
        TypesLib.Juror memory juror = ds.getJuror(msg.sender);

        // ---------------- Validation ----------------
        if (stakeAmount < ds.minStakeAmount() || stakeAmount > ds.maxStakeAmount()) {
            revert JurorManager__InvalidStakeAmount();
        }
        if (juror.stakeAmount > 0) {
            revert JurorManager__AlreadyRegistered();
        }

        // ---------------- Transfer ----------------
        bloomToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // ---------------- Create Juror ----------------
        uint256 score = ds.computeScore(stakeAmount, 0);

        TypesLib.Juror memory newJuror = TypesLib.Juror({
            jurorAddress: msg.sender,
            stakeAmount: stakeAmount,
            reputation: 0,
            missedVotesCount: 0,
            score: score,
            lastWithdrawn: 0
        });

        // ---------------- Update State ----------------
        ds.updateJuror(msg.sender, newJuror); // store juror first
        ds.updateMaxScore(score); // pass score directly

        // ---------------- Global Lists ----------------
        ds.pushIntoAllJurorAddresses(msg.sender);
        ds.pushToActiveJurorAddresses(msg.sender);

        // ---------------- Emit Event ----------------
        emit JurorRegistered(msg.sender, stakeAmount);
    }

    function stakeMore(uint256 additionalStake) external {
        if (additionalStake == 0) revert JurorManager__ZeroAmount();

        // pull juror struct from ds (external call, returns memory copy)
        TypesLib.Juror memory juror = ds.getJuror(msg.sender);
        if (juror.jurorAddress == address(0)) revert JurorManager__NotRegistered();

        uint256 newStakeAmount;
        unchecked {
            newStakeAmount = juror.stakeAmount + additionalStake;
        }

        if (newStakeAmount > ds.maxStakeAmount()) {
            revert JurorManager__InvalidStakeAmount();
        }

        // update ds first (state changes before external ERC20 call)
        ds.updateJurorStakeAmount(msg.sender, newStakeAmount);

        // then transfer tokens
        bloomToken.safeTransferFrom(msg.sender, address(this), additionalStake);

        emit MoreStaked(msg.sender, additionalStake, newStakeAmount);
    }

    /**
     * @notice Selects jurors for a given dispute based on experience and fairness constraints.
     * @param disputeId The ID of the dispute for which jurors are being selected.
     */

    // Note - only the dispute creator will call selectJurors
    // 5 jurors will be assigned to the dispute.
    function selectJurors(uint256 disputeId) external returns (uint256) {
        address[] memory disputeJurors = ds.getDisputeJurors(disputeId);
        if (disputeJurors.length > 0) revert JurorManager__AlreadyAssignedJurors();

        // Define how many experienced and newbie jurors are needed
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;

        // Get active pools once
        (address[] memory activeExperienced, address[] memory activeNewbies) = _getActivePools();

        // Pool size checks
        if (activeExperienced.length < expNeeded) revert JurorManager__InsufficientExperienced();
        if (activeNewbies.length < newbieNeeded) revert JurorManager__InsufficientNewbies();

        // Save requirements + snapshot of active pools
        experienceNeededByDispute[disputeId] = expNeeded;
        newbieNeededByDispute[disputeId] = newbieNeeded;
        activeExperiencedByDispute[disputeId] = activeExperienced;
        activeNewbiesByDispute[disputeId] = activeNewbies;

        // Request randomness from Chainlink VRF
        uint256 requestId = requestRandomness(ds.callbackGasLimit(), ds.requestConfirmations(), ds.numWords());
        s_requests[requestId] = TypesLib.RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(ds.callbackGasLimit()),
            randomWords: new uint256[](0),
            fulfilled: false
        });

        requestIds.push(requestId);
        lastRequestId = requestId;
        requestIdToDispute[requestId] = disputeId;
        requestToType[requestId] = RequestType.INITIAL;

        emit RequestSent(requestId, ds.numWords());

        return requestId;
    }

    // ------------------- VRF CALLBACK -------------------
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        if (s_requests[_requestId].paid <= 0) revert JurorManager__RequestNotFound();
        s_requests[_requestId].fulfilled = true;

        uint256 disputeId = requestIdToDispute[_requestId];
        RequestType requestType = requestToType[_requestId];

        if (requestType == RequestType.INITIAL) {
            uint256 expNeeded = experienceNeededByDispute[disputeId];
            uint256 newbieNeeded = newbieNeededByDispute[disputeId];
            uint256 total = expNeeded + newbieNeeded;

            address[] memory activeExperienced = activeExperiencedByDispute[disputeId];
            address[] memory activeNewbies = activeNewbiesByDispute[disputeId];

            // Select experienced and newbie jurors
            address[] memory selectedExperienced =
                _selectJurors(expNeeded, _randomWords[0], activeExperienced, disputeId);

            address[] memory selectedNewbies = _selectJurors(newbieNeeded, _randomWords[1], activeNewbies, disputeId);

            // Combine selected jurors
            address[] memory selected = new address[](total);
            uint256 idx = 0;
            for (uint256 i = 0; i < selectedExperienced.length; i++) {
                selected[idx++] = selectedExperienced[i];
            }
            for (uint256 i = 0; i < selectedNewbies.length; i++) {
                selected[idx++] = selectedNewbies[i];
            }

            ds.updateDisputeJurors(disputeId, selected);
            ds.updateDisputeTimer(disputeId, TypesLib.Timer(disputeId, block.timestamp, ds.votingPeriod(), 0));

            ds.updateDisputeStatus(disputeId, true);

            emit JurorsSelected(disputeId, selected);
        } else if (requestType == RequestType.TIE_BREAKER) {
            // Adding the juror to the list of candidates
            uint256 jurorNeeded = 1;
            address[] memory pool = poolToPickFrom[disputeId];
            address[] memory eligiblePool = _getEligiblePool(pool, disputeId);

            uint256 pickIndex = _randomWords[0] % eligiblePool.length;
            address selectedJurorAddress = eligiblePool[pickIndex];

            address[] memory newJurors = new address[](jurorNeeded);
            newJurors[0] = selectedJurorAddress;
            // Check status of the user to know if they already have more than the max ongoing dispute count to prevent them from subsequent selections;

            // Add the juror to candidate list
            _addJurorsToCandidateList(disputeId, newJurors);

            // Give them some time to vote.
            tieBreakerJuror[disputeId] = selectedJurorAddress;

            emit TieSelectionCompleted(disputeId, selectedJurorAddress);
        }
    }

    function _getEligiblePool(address[] memory pool, uint256 _disputeId) internal view returns (address[] memory) {
        address[] memory eligible = new address[](pool.length);
        uint256 index;
        uint256 minStakeAmount = ds.minStakeAmount();
        uint256 ongoingDisputeThreshold = ds.ongoingDisputeThreshold();
        uint256 missedVoteThreshold = ds.missedVoteThreshold();

        for (uint256 i = 0; i < pool.length; i++) {
            address jurorAddress = pool[i];
            TypesLib.Juror memory juror = ds.getJuror(jurorAddress);
            uint256 ongoingDisputeCount = ds.ongoingDisputeCount(jurorAddress);
            TypesLib.Candidate memory candidate = ds.getDisputeCandidate(_disputeId, jurorAddress);
            bool isSelected = candidate.jurorAddress != address(0);
            // bool isSelected = ds.isDisputeCandidate(_disputeId, jurorAddress).jurorAddress != address(0);

            if (
                juror.missedVotesCount >= missedVoteThreshold || juror.stakeAmount < minStakeAmount
                    || ongoingDisputeCount >= ongoingDisputeThreshold || isSelected
            ) {
                continue;
            }
            eligible[index++] = jurorAddress;
        }

        // shrink array
        assembly {
            mstore(eligible, index)
        }
        return eligible;
    }

    function _getActivePools() internal view returns (address[] memory experienced, address[] memory newbies) {
        address[] memory activeJurorAddresses = ds.getActiveJurorAddresses();

        experienced = new address[](activeJurorAddresses.length);
        uint256 expIndex;
        newbies = new address[](activeJurorAddresses.length);
        uint256 newIndex;

        for (uint256 i = 0; i < activeJurorAddresses.length; i++) {
            TypesLib.Juror memory juror = ds.getJuror(activeJurorAddresses[i]); // jurors[activeJurorAddresses[i]];

            if (juror.stakeAmount >= ds.minStakeAmount()) {
                uint256 score = juror.score;
                uint256 thresholdScore = ds.thresholdPercent() * ds.maxScore() / MAX_PERCENT;

                if (score >= thresholdScore) {
                    experienced[expIndex++] = juror.jurorAddress;
                } else {
                    newbies[newIndex++] = juror.jurorAddress;
                }
            }
        }

        // shrink array
        assembly {
            mstore(experienced, expIndex)
        }
        assembly {
            mstore(newbies, newIndex)
        }
        return (experienced, newbies);
    }

    function _selectJurors(uint256 needed, uint256 rand, address[] memory pool, uint256 disputeId)
        internal
        returns (address[] memory selected)
    {
        selected = new address[](needed);
        uint256 idx = 0;

        for (uint256 i = 0; i < needed; i++) {
            uint256 pickIdx = rand % pool.length;
            address jurorAddr = pool[pickIdx];

            TypesLib.Juror memory juror = ds.getJuror(jurorAddr);
            selected[idx++] = jurorAddr;

            // Update candidate mapping
            TypesLib.Candidate memory candidate = TypesLib.Candidate(
                disputeId,
                jurorAddr,
                juror.stakeAmount,
                juror.reputation,
                selectionScoresTemp[disputeId][jurorAddr],
                false
            );
            ds.updateDisputeCandidate(disputeId, jurorAddr, candidate);
            ds.pushIntoJurorDisputeHistory(jurorAddr, disputeId);

            // Swap-remove
            pool[pickIdx] = pool[pool.length - 1];
            assembly {
                mstore(pool, sub(mload(pool), 1))
            }

            // Update randomness
            rand = uint256(keccak256(abi.encodePacked(rand, i)));
        }
    }

    function checkUpkeep(bytes calldata /*checkData*/ )
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256[] memory allDisputes = ds.getAllDisputes();
        uint256[] memory disputesToExtend = new uint256[](allDisputes.length);

        uint256 count = 0;

        for (uint256 i = 0; i < allDisputes.length; i++) {
            uint256 disputeId = allDisputes[i];

            // Skip disputes that are no longer in voting;
            if (!ds.ongoingDisputes(disputeId)) continue;

            // Get timer info;
            TypesLib.Timer memory timer = ds.getDisputeTimer(disputeId);
            if (timer.extendDuration > 0) continue;

            if (block.timestamp <= timer.startTime + timer.standardVotingDuration) continue;

            // Let's check if quorum is met
            uint256 confirmedVotes = _getConfirmedVotes(disputeId);
            uint256 quorum = ds.getDisputeJurors(disputeId).length - 2;
            if (confirmedVotes < quorum) {
                disputesToExtend[count++] = disputeId;
            }
        }

        if (count > 0) {
            upkeepNeeded = true;

            // Let's trim array to actual size.
            assembly {
                mstore(disputesToExtend, count)
            }

            performData = abi.encode(disputesToExtend);
        } else {
            upkeepNeeded = false;
            performData = "";
        }
    }

    function performUpkeep(bytes calldata performData) external {
        uint256[] memory disputesToExtend = abi.decode(performData, (uint256[]));
        for (uint256 i = 0; i < disputesToExtend.length; i++) {
            _extendVotingPeriod(disputesToExtend[i]);
        }
    }

    function _getConfirmedVotes(uint256 disputeId) internal view returns (uint256 confirmed) {
        confirmed = 0;
        address[] memory jurors = ds.getDisputeJurors(disputeId);
        for (uint256 i = 0; i < jurors.length; i++) {
            TypesLib.Vote memory jurorVote = ds.getDisputeVote(disputeId, jurors[i]);
            if (jurorVote.support != address(0)) confirmed++;
        }
        return confirmed;
    }

    function vote(uint256 disputeId, address support) external {
        // Validate input
        if (support == address(0)) revert JurorManager__MustVote();

        // Check voting period
        TypesLib.Timer memory timer = ds.getDisputeTimer(disputeId);

        // Make sure that users cannot vote when time elapses.
        _validateTimeStamp(disputeId, timer);

        if (block.timestamp > timer.startTime + timer.standardVotingDuration + timer.extendDuration) {
            revert JurorManager__VotingPeriodExpired();
        }

        // Check eligibility
        address[] memory jurors = ds.getDisputeJurors(disputeId);
        if (!checkVoteEligibility(jurors, msg.sender)) revert JurorManager__NotEligible();

        // Ensure the voter has not voted yet
        TypesLib.Vote memory jurorVote = ds.getDisputeVote(disputeId, msg.sender);
        if (jurorVote.jurorAddress != address(0)) revert JurorManager__AlreadyVoted();

        // Ensure max votes not exceeded
        TypesLib.Vote[] memory allVotes = ds.getAllDisputeVotes(disputeId);
        if (allVotes.length + 1 > jurors.length) revert JurorManager__MaxVoteExceeded();

        // Record the vote
        TypesLib.Dispute memory dispute = ds.getDispute(disputeId);
        TypesLib.Vote memory newVote =
            TypesLib.Vote({jurorAddress: msg.sender, disputeId: disputeId, dealId: dispute.dealId, support: support});

        ds.updateDisputeVote(disputeId, msg.sender, newVote);
        ds.pushIntoAllDisputeVotes(disputeId, newVote);

        // Emit event
        emit Voted(disputeId, msg.sender, support);
    }

    function _validateTimeStamp(uint256 disputeId, TypesLib.Timer memory timer) private view {
        address tieBreaker = tieBreakerJuror[disputeId];
        uint256 maxTime = timer.startTime + timer.standardVotingDuration + timer.extendDuration;

        if (tieBreaker != address(0)) {
            maxTime += tieBreakingDuration;
        }

        if (block.timestamp > maxTime) {
            revert JurorManager__VotingPeriodExpired();
        }
    }

    function checkVoteEligibility(address[] memory disputeVoters, address voter)
        public
        pure
        returns (bool isEligible)
    {
        // You are eligible if you are one of the assigned jurors
        for (uint256 i = 0; i < disputeVoters.length; i++) {
            if (disputeVoters[i] == voter) {
                isEligible = true;
                break;
            }
        }
    }

    function _extendVotingPeriod(uint256 _disputeId) internal {
        // Here, the voting period is extended if the number of voters is less than the quorum;
        TypesLib.Timer memory timer = ds.getDisputeTimer(_disputeId); // disputeTimer[_disputeId];

        // If alrady extended, do nothing;
        if (timer.extendDuration > 0) return;

        // If not, extend the voting period;
        ds.updateDisputeTimer(
            _disputeId,
            TypesLib.Timer(_disputeId, timer.startTime, timer.standardVotingDuration, ds.extendingDuration())
        );

        emit ExtendedVotingPeriod(_disputeId);
    }

    function breakTie(uint256 _disputeId) external returns (uint256) {
        // Incase there is a tie breaker, this will help in resolving that.

        // This will be called only after the voting period has elapsed
        TypesLib.Timer memory timer = ds.getDisputeTimer(_disputeId); // disputeTimer[_disputeId];
        if (block.timestamp < timer.startTime + timer.standardVotingDuration + timer.extendDuration) {
            revert JurorManager__VotingNotFinished();
        }

        // Select a random juror
        // Get the list of active newbies and experienced jurors;
        (address[] memory activeExperienced, address[] memory activeNewbies) = _getActivePools();

        // Pool size checks
        if (activeExperienced.length > 1) {
            poolToPickFrom[_disputeId] = activeExperienced;
        } else if (activeNewbies.length > 1) {
            poolToPickFrom[_disputeId] = activeNewbies;
        } else {
            revert JurorManager__InsufficientJurors();
        }

        // Request randomness from Chainlink VRF
        uint256 requestId = requestRandomness(ds.callbackGasLimit(), ds.requestConfirmations(), 1);
        s_requests[requestId] = TypesLib.RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(ds.callbackGasLimit()),
            randomWords: new uint256[](0),
            fulfilled: false
        });

        requestIds.push(requestId);
        lastRequestId = requestId;
        requestIdToDispute[requestId] = _disputeId;
        requestToType[requestId] = RequestType.TIE_BREAKER;

        emit RequestSent(requestId, 1);

        return requestId;
    }

    function _addJurorsToCandidateList(uint256 _disputeId, address[] memory selectedJurorAddresses) internal {
        for (uint256 i = 0; i < selectedJurorAddresses.length; i++) {
            address jurorAddress = selectedJurorAddresses[i];
            TypesLib.Juror memory juror = ds.getJuror(jurorAddress); // jurors[jurorAddress];

            ds.updateDisputeCandidate(
                _disputeId,
                jurorAddress,
                TypesLib.Candidate({
                    disputeId: _disputeId,
                    jurorAddress: juror.jurorAddress,
                    stakeAmount: juror.stakeAmount,
                    reputation: juror.reputation,
                    score: 0,
                    missed: false
                })
            );

            // Set to active and pop from activeJurorAddresses
            ds.pushIntoDisputeJurors(jurorAddress, _disputeId);
            // disputeJurors[_disputeId].push(jurorAddress);

            ds.popFromActiveJurorAddresses(jurorAddress);
            // _popFromActiveJurorAddresses(jurorAddress);

            ds.updateOngoingDisputeCount(jurorAddress, ds.ongoingDisputeCount(jurorAddress) + 1);
            // ongoingDisputeCount[jurorAddress] += 1;

            // If there are 3+ ongoing disputes, remove from active jurors
            bool isPresent = ds.isInActiveJurorAddresses(jurorAddress);
            if (ds.ongoingDisputeCount(jurorAddress) > ds.ongoingDisputeThreshold() && isPresent) {
                ds.popFromActiveJurorAddresses(jurorAddress);

                // _popFromActiveJurorAddresses(jurorAddress);
            }
        }
    }

    function withdrawStake(uint256 _stakeAmount) external {
        TypesLib.Juror memory juror = ds.getJuror(msg.sender); // jurors[msg.sender];

        if (block.timestamp < juror.lastWithdrawn + ds.cooldownDuration()) {
            revert JurorManager__WithdrawalCooldownNotOver();
        }

        uint256 totalStakedAmount = juror.stakeAmount;
        uint256 lockedAmount = (ds.lockedPercentage() * totalStakedAmount) / MAX_PERCENT;
        uint256 availableToWithdraw = totalStakedAmount - lockedAmount;

        if (_stakeAmount > availableToWithdraw) {
            revert JurorManager__NotEnoughStakeToWithdraw();
        }

        bloomToken.safeTransfer(msg.sender, _stakeAmount);

        ds.updateJurorStakeAmount(msg.sender, juror.stakeAmount - _stakeAmount);
        // juror.stakeAmount -= _stakeAmount;

        ds.updateJurorLastWithdrawn(msg.sender, block.timestamp);
        // juror.lastWithdrawn = block.timestamp;

        emit StakeWithdrawn(msg.sender, _stakeAmount);
    }

    function finishDispute(uint256 _disputeId) external onlyOwner {
        // Check if voting time has elapsed;
        TypesLib.Timer memory appealDisputeTimer = ds.getDisputeTimer(_disputeId);
        TypesLib.Dispute memory disputeToFinish = ds.getDispute(_disputeId);

        if (disputeToFinish.winner != address(0)) {
            // revert DisputeManager__AlreadyFinished();
        }

        if (
            block.timestamp
                < appealDisputeTimer.startTime + appealDisputeTimer.standardVotingDuration
                    + appealDisputeTimer.extendDuration
        ) {
            // revert DisputeManager__NotFinished();
        }
        TypesLib.Vote[] memory allVotes = ds.getAllDisputeVotes(_disputeId);

        // console.log("Length of all votes: ", allVotes.length);

        // Determine the winner;
        (bool tie, address winner, address loser, uint256 winnerCount, uint256 loserCount) =
            _determineWinner(_disputeId, allVotes);

        // Update the reward and reputation accordingly
        _distributeRewardAndReputation(tie, _disputeId, winner, winnerCount);

        // Update all the states
        ds.updateDisputeWinner(_disputeId, winner);
        // disputes[_disputeId].winner = winner;

        // Emit events;
        // emit DisputeFinished(_disputeId, winner, loser, winnerCount, loserCount);
    }

    function _determineWinner(uint256 _disputeId, TypesLib.Vote[] memory allVotes)
        internal
        view
        returns (bool tie, address winner, address loser, uint256 winnerCount, uint256 loserCount)
    {
        TypesLib.Dispute memory d = ds.getDispute(_disputeId);
        uint256 initiatorCount;
        uint256 againstCount;

        for (uint256 i; i < allVotes.length; i++) {
            allVotes[i].support == d.initiator ? initiatorCount++ : againstCount++;
        }

        if (initiatorCount == againstCount) {
            return (true, address(0), address(0), 0, 0);
        }

        bool initiatorWins = initiatorCount > againstCount;
        winner = initiatorWins ? d.initiator : (d.initiator == d.sender ? d.receiver : d.sender);
        loser = initiatorWins ? (d.initiator == d.sender ? d.receiver : d.sender) : d.initiator;

        return (
            false,
            winner,
            loser,
            initiatorWins ? initiatorCount : againstCount,
            initiatorWins ? againstCount : initiatorCount
        );
    }

    function _distributeRewardAndReputation(bool tie, uint256 disputeId, address winner, uint256 winnerCount)
        internal
    {
        if (tie) return;

        uint256 totalSlashed;
        uint256 totalWinnerStake;
        uint256 votedJurorCount;
        address[] memory jurors = ds.getDisputeJurors(disputeId);
        address[] memory winners = new address[](winnerCount);
        uint256 winIndex;

        TypesLib.Dispute memory dispute = ds.getDispute(disputeId);
        uint256 baseFee = (ds.basePercentage() * dispute.disputeFee) / MAX_PERCENT;

        // Process all jurors (vote, slash, base fee, reputation)
        for (uint256 i = 0; i < jurors.length; i++) {
            address jurorAddr = jurors[i];
            TypesLib.Candidate memory cand = ds.getDisputeCandidate(disputeId, jurorAddr);
            TypesLib.Vote memory jurorVote = ds.getDisputeVote(disputeId, jurorAddr);

            // decrease ongoing dispute count
            ds.updateOngoingDisputeCount(jurorAddr, ds.ongoingDisputeCount(jurorAddr) - 1);

            uint256 newStake;
            uint256 newRep;

            if (jurorVote.support != address(0)) {
                votedJurorCount++;
                ds.updateJurorTokenPayments(jurorAddr, dispute.feeTokenAddress, baseFee);

                if (jurorVote.support == winner) {
                    winners[winIndex++] = jurorAddr;
                    totalWinnerStake += cand.stakeAmount;
                } else {
                    uint256 slashAmt = (cand.stakeAmount * ds.slashPercentage()) / MAX_PERCENT;
                    totalSlashed += slashAmt;

                    TypesLib.Juror memory juror = ds.getJuror(jurorAddr);
                    newStake = juror.stakeAmount - slashAmt;
                    ds.updateJurorStakeAmount(jurorAddr, newStake);

                    // reduce reputation
                    newRep = _applyReputationDelta(juror.reputation, -(int256(ds.lambda()) * int256(ds.k())) / 1e18);
                    ds.updateJurorReputation(jurorAddr, newRep);
                    ds.updateJurorScore(jurorAddr);
                }
            } else {
                // No vote → separate slash and reputation penalty
                uint256 slashAmt = (cand.stakeAmount * ds.noVoteSlashPercentage()) / MAX_PERCENT;
                TypesLib.Juror memory juror = ds.getJuror(jurorAddr);
                newStake = juror.stakeAmount - slashAmt;
                ds.updateJurorStakeAmount(jurorAddr, newStake);

                newRep = _applyReputationDelta(juror.reputation, -(int256(ds.lambda()) * int256(ds.noVoteK())) / 1e18);
                ds.updateJurorReputation(jurorAddr, newRep);
                ds.updateJurorScore(jurorAddr);

                if (!cand.missed) {
                    ds.updateCandidateMissedStatus(disputeId, jurorAddr, true);
                    ds.updateJurorMissedVotesCount(jurorAddr, juror.missedVotesCount + 1);
                }
            }
        }

        // Distribute rewards to winners
        if (winnerCount > 0) {
            uint256 remainingPercent = MAX_PERCENT - (ds.basePercentage() * votedJurorCount);
            uint256 remainingFee = (remainingPercent * dispute.disputeFee) / MAX_PERCENT;
            uint256 indivFee = remainingFee / winnerCount;
            uint256 distributed = indivFee * winnerCount;
            uint256 dust = remainingFee - distributed; // remainder goes to last juror

            uint256 newStake;
            uint256 newRep;

            for (uint256 i = 0; i < winnerCount; i++) {
                address jurorAddr = winners[i];
                TypesLib.Candidate memory cand = ds.getDisputeCandidate(disputeId, jurorAddr);

                uint256 reward = (cand.stakeAmount * totalSlashed) / totalWinnerStake;
                TypesLib.Juror memory juror = ds.getJuror(jurorAddr);
                newStake = juror.stakeAmount + reward;
                ds.updateJurorStakeAmount(jurorAddr, newStake);

                // increase reputation
                newRep = _applyReputationDelta(juror.reputation, (int256(ds.lambda()) * int256(ds.k())) / 1e18);
                ds.updateJurorReputation(jurorAddr, newRep);
                ds.updateJurorScore(jurorAddr);

                // final payout = base fee + indivFee (+ dust for last juror)
                uint256 payout = baseFee + indivFee;
                if (i == winnerCount - 1 && dust > 0) {
                    payout += dust;
                }

                uint256 prev = ds.getJurorTokenPayment(jurorAddr, dispute.feeTokenAddress);
                ds.updateJurorTokenPayments(jurorAddr, dispute.feeTokenAddress, prev + payout);

                ds.updateDisputeToJurorPayment(
                    disputeId,
                    jurorAddr,
                    TypesLib.PaymentType({disputeId: disputeId, tokenAddress: dispute.feeTokenAddress, amount: payout})
                );
            }
        }

        balanceMaxScore(jurors);
    }

    // helper to avoid underflow in reputation updates
    function _applyReputationDelta(uint256 oldRep, int256 delta) private pure returns (uint256) {
        int256 updated = int256(oldRep) + delta;
        return updated > 0 ? uint256(updated) : 0;
    }

    function balanceMaxScore(address[] memory jurorAddresses) internal {
        for (uint256 i = 0; i < jurorAddresses.length; i++) {
            ds.balanceMaxScore(jurorAddresses[i]);
        }
    }
}
