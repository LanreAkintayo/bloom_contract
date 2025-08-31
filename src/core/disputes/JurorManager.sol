// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {VRFV2WrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {DisputeManager} from "./DisputeManger.sol";

contract JurorManager is VRFV2WrapperConsumerBase, ConfirmedOwner, DisputeManager {
    using SafeERC20 for IERC20;

    // For randomness;
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => Candidate[]) private experiencedPoolTemporary;
    mapping(uint256 => Candidate[]) private newbiePoolTemporary;
    mapping(uint256 => uint256) private experienceNeededByDispute;
    mapping(uint256 => uint256) private newbieNeededByDispute;
    mapping(uint256 => uint256) private requestIdToDispute;

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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event JurorRegistered(address indexed juror, uint256 stakeAmount);
    event MinStakeAmountUpdated(uint256 indexed newMinStakeAmount);
    event MaxStakeAmountUpdated(uint256 indexed newMaxStakeAmount);
    event MoreStaked(address indexed juror, uint256 indexed additionalStaked);
    event JurorsSelected(uint256 indexed disputeId, Candidate[] indexed selected);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);
    event Voted(uint256 indexed disputeId, address indexed jurorAddress, address indexed support);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _bloomTokenAddress,
        address _linkAddress,
        address _wrapperAddress,
        address _escrowAddress,
        address _feeControllerAddress
    )
        ConfirmedOwner(msg.sender)
        VRFV2WrapperConsumerBase(_linkAddress, _wrapperAddress)
        DisputeManager(_escrowAddress, _feeControllerAddress)
    {
        bloomToken = IERC20(_bloomTokenAddress);
        linkAddress = _linkAddress;
        wrapperAddress = _wrapperAddress;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    function registerJuror(uint256 stakeAmount) external {
        if (stakeAmount < minStakeAmount || stakeAmount > maxStakeAmount) {
            revert JurorManager__InvalidStakeAmount();
        }

        if (jurors[msg.sender].stakeAmount > 0) {
            revert JurorManager__AlreadyRegistered();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // // Register juror
        Juror memory juror;
        juror.jurorAddress = msg.sender;
        juror.stakeAmount = stakeAmount;
        juror.reputation = 0;
        juror.missedVotesCount = 0;

        jurors[msg.sender] = juror;

        // @complete Add to the array of all jurors

        emit JurorRegistered(msg.sender, stakeAmount);
    }

    function stakeMore(uint256 additionalStake) external {
        if (additionalStake == 0) {
            revert JurorManager__ZeroAmount();
        }

        Juror storage juror = jurors[msg.sender];

        if (juror.jurorAddress == address(0)) {
            revert JurorManager__NotRegistered();
        }

        uint256 newStakeAmount = juror.stakeAmount + additionalStake;

        if (newStakeAmount > maxStakeAmount) {
            revert JurorManager__InvalidStakeAmount();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), additionalStake);

        // Update juror stake
        juror.stakeAmount = newStakeAmount;

        emit MoreStaked(msg.sender, additionalStake);
    }

    function computeScore(
        uint256 stakeAmount,
        uint256 reputation,
        uint256 _maxStake,
        uint256 maxReputation,
        uint256 alphaFP,
        uint256 betaFP
    ) public pure returns (uint256) {
        uint256 score = (alphaFP * stakeAmount / _maxStake) + (betaFP * (reputation + 1) / (maxReputation + 1));
        return score;
    }

    function selectJurors(
        uint256 disputeId,
        uint256 thresholdFP,
        uint256 alphaFP,
        uint256 betaFP,
        uint256 expNeeded,
        uint256 newbieNeeded,
        uint256 experiencedPoolSize
    ) external onlyOwner {
        // Don't select juror for a dispute that already has a juror
        if (disputeJurors[disputeId].length > 0) {
            revert JurorManager__AlreadyAssignedJurors();
        }

        // To verify the experiencedPoolSize with the one computed off-chain
        uint256 countAbove = 0;

        Candidate[] memory experiencedPoolTemp = new Candidate[](allJurors.length);
        Candidate[] memory newbiePoolTemp = new Candidate[](allJurors.length);
        uint256 expIndex = 0;
        uint256 newIndex = 0;

        uint256 maxStake = 1;
        uint256 maxReputation = 1;

        //// find max stake & reputation
        for (uint256 i = 0; i < allJurors.length; i++) {
            Juror memory juror = allJurors[i];

            // Make sure that we can only select a juror that is currently inactive and their stake amount is greater than the minimum stake amount
            if (isJurorActive[juror.jurorAddress] && juror.stakeAmount >= minStakeAmount) {
                if (juror.stakeAmount > maxStake) maxStake = juror.stakeAmount;
                if (juror.reputation > maxReputation) maxReputation = juror.reputation;
            }
        }

        // compute selection scores and assign to pools
        for (uint256 i = 0; i < allJurors.length; i++) {
            Juror memory juror = allJurors[i];

            if (isJurorActive[juror.jurorAddress] && juror.stakeAmount >= minStakeAmount) {
                uint256 score =
                    computeScore(juror.stakeAmount, juror.reputation, maxStake, maxReputation, alphaFP, betaFP);

                if (score >= thresholdFP) {
                    experiencedPoolTemp[expIndex++] =
                        Candidate(disputeId, juror.jurorAddress, juror.stakeAmount, juror.reputation, score);
                    countAbove++;
                } else {
                    newbiePoolTemp[newIndex++] =
                        Candidate(disputeId, juror.jurorAddress, juror.stakeAmount, juror.reputation, score);
                }
            }
        }

        if (countAbove != experiencedPoolSize) {
            revert JurorManager__ThresholdMismatched();
        }

        // resize arrays
        assembly {
            mstore(experiencedPoolTemp, expIndex)
        }
        assembly {
            mstore(newbiePoolTemp, newIndex)
        }

        // store temp pools for VRF callback
        experiencedPoolTemporary[disputeId] = experiencedPoolTemp;
        newbiePoolTemporary[disputeId] = newbiePoolTemp;
        experienceNeededByDispute[disputeId] = expNeeded;
        newbieNeededByDispute[disputeId] = newbieNeeded;

        // request randomness from Chainlink VRF
        uint256 requestId = requestRandomness(callbackGasLimit, requestConfirmations, numWords);
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        requestIdToDispute[requestId] = disputeId;
    }

    // ------------------- VRF CALLBACK -------------------
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        if (s_requests[_requestId].paid <= 0) {
            revert JurorManager__RequestNotFound();
        }
        s_requests[_requestId].fulfilled = true;

        uint256 randomness = _randomWords[0];
        uint256 disputeId = requestIdToDispute[_requestId];

        Candidate[] memory experiencedPool = experiencedPoolTemporary[disputeId];
        Candidate[] memory newbiePool = newbiePoolTemporary[disputeId];

        uint256 expNeeded = experienceNeededByDispute[disputeId];
        uint256 newbieNeeded = newbieNeededByDispute[disputeId];
        uint256 total = expNeeded + newbieNeeded;

        Candidate[] memory selected = new Candidate[](total);
        uint256 idx = 0;
        uint256 rand = randomness;

        // pick experienced jurors
        for (uint256 i = 0; i < expNeeded; i++) {
            uint256 pickIdx = rand % experiencedPool.length;
            selected[idx++] = experiencedPool[pickIdx];

            // Track all the disputes per juror
            jurorDisputeHistory[experiencedPool[pickIdx].jurorAddress].push(disputeId);

            // swap-remove
            experiencedPool[pickIdx] = experiencedPool[experiencedPool.length - 1];
            assembly {
                mstore(experiencedPool, sub(mload(experiencedPool), 1))
            }

            rand = uint256(keccak256(abi.encodePacked(rand, i))) % experiencedPool.length;
        }

        // pick newbie jurors
        for (uint256 i = 0; i < newbieNeeded; i++) {
            uint256 pickIdx = rand % newbiePool.length;
            selected[idx++] = newbiePool[pickIdx];

            // Track all the disputes per juror
            jurorDisputeHistory[experiencedPool[pickIdx].jurorAddress].push(disputeId);

            // swap-remove
            newbiePool[pickIdx] = newbiePool[newbiePool.length - 1];
            assembly {
                mstore(newbiePool, sub(mload(newbiePool), 1))
            }

            rand = uint256(keccak256(abi.encodePacked(rand, i))) % newbiePool.length;
        }

        // mark jurors active
        for (uint256 i = 0; i < selected.length; i++) {
            isJurorActive[selected[i].jurorAddress] = true;
        }

        disputeJurors[disputeId] = selected;
        disputeTimer[disputeId] = Timer(disputeId, block.timestamp + votingPeriod, 0);

        emit JurorsSelected(disputeId, selected);
    }

    function vote(uint256 disputeId, address support) external {
        // Make sure that the caller is one of the selected juror for the dispute
        bool isEligible = checkVoteEligibility(disputeId, msg.sender);
        uint256 correspondingDealId = disputes[disputeId].dealId;

        if (!isEligible) {
            revert JurorManager__NotEligible();
        }

        // Make sure voter has not voted before;
        if (disputeVotes[disputeId][msg.sender].jurorAddress != address(0)) {
            revert JurorManager__AlreadyVoted();
        }

        // Make sure that the number of votes is equal to the number of candidates selected to vote;
        if (allDisputeVotes[disputeId].length + 1 > disputeJurors[disputeId].length) {
            revert JurorManager__MaxVoteExceeded();
        }
        // Then you vote
        Vote memory newVote = Vote(msg.sender, disputeId, correspondingDealId, support);

        disputeVotes[disputeId][msg.sender] = newVote;
        allDisputeVotes[disputeId].push(newVote);

        // Emit event
        emit Voted(disputeId, msg.sender, support);
    }

    function checkVoteEligibility(uint256 disputeId, address voter) public view returns (bool isEligible) {
        Candidate[] memory disputeVoters = disputeJurors[disputeId];

        for (uint256 i = 0; i < disputeVoters.length; i++) {
            if (disputeVoters[i].jurorAddress == voter) {
                isEligible = true;
                break;
            }
        }
    }

    function finishDispute(uint256 _disputeId) external onlyOwner {
        // Check if voting time has elapsed;
        Timer memory disputeTimer = disputeTimer[_disputeId];

        if (block.timestamp < disputeTimer.endingTime) {
            revert JurorManager__NotFinished();
        }
        Vote[] memory allVotes = allDisputeVotes[_disputeId];

        // Determine the winner;
        (bool tie, address winner, , uint256 winnerCount, ) =
            _determineWinner(_disputeId, allVotes);

        // Update the reward and reputation accordingly
        _distributeRewardAndReputation(tie, _disputeId, winner, winnerCount);

        // Update all the states
        

        // Emit events;

      
    }

    // function penalizeJuror(uint256 )

    function _distributeRewardAndReputation(bool tie, uint256 _disputeId, address winner, uint256 winnerCount)
        internal
    {
        if (tie) return;

        uint256 totalAmountSlashed;
        uint256 totalWinnerStakedAmount;
        Candidate[] memory selectedJurors = disputeJurors[_disputeId];
        Candidate[] memory winnersAlone = new Candidate[](winnerCount);
        uint256 winnerId = 0;

        // Calculate the total amount slashed from the losers
        for (uint256 i = 0; i < selectedJurors.length; i++) {
            // Make sure you deal with only the jurors that voted;
            Candidate memory currentCandidate = selectedJurors[i];
            address currentJurorAddress = currentCandidate.jurorAddress;
            uint256 currentStakeAmount = currentCandidate.stakeAmount;
            Vote memory currentVote = disputeVotes[_disputeId][currentJurorAddress];

            if (currentVote.jurorAddress != address(0)) {
                if (currentVote.support != winner) {
                    uint256 amountDeducted = (currentStakeAmount * slashPercentage) / MAX_PERCENT;
                    totalAmountSlashed += amountDeducted;

                    if (currentCandidate.jurorAddress != owner()) {
                        Juror storage juror = jurors[currentCandidate.jurorAddress];
                        // Update juror stake amount
                        juror.stakeAmount -= amountDeducted;

                        // Update the juror reputation;
                        uint256 oldReputation = juror.reputation;
                        int256 newReputation = int256(oldReputation) - (int256(lambda) * int256(k)) / 1e18;

                        juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;

                        // We don't need to update the Candidate struct because it is only used to note the staked value as at when selected to vote.
                    }
                } else {
                    totalWinnerStakedAmount += currentCandidate.stakeAmount;
                    winnersAlone[winnerId++] = (currentCandidate);
                }
            } else {
                // The candidates here did not vote at all but they were chosen

                uint256 deductedAmount = currentStakeAmount * noVoteSlashPercentage / MAX_PERCENT;
                Juror storage juror = jurors[currentJurorAddress];
                juror.stakeAmount -= deductedAmount;

                // Update the juror reputation;
                uint256 oldReputation = juror.reputation;
                int256 newReputation = int256(oldReputation) - (int256(lambda) * int256(noVoteK)) / 1e18;

                juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;
                juror.missedVotesCount += 1;
            }
        }

        // Let's distribute to the winners;
        for (uint256 i = 0; i < winnersAlone.length; i++) {
            Candidate memory currentCandidate = winnersAlone[i];
            uint256 rewardAmount = (currentCandidate.stakeAmount * totalAmountSlashed) / totalWinnerStakedAmount;

            Juror storage juror = jurors[currentCandidate.jurorAddress];
            juror.stakeAmount += rewardAmount;

            // Update the reputation
            uint256 oldReputation = juror.reputation;
            int256 newReputation = int256(oldReputation) + (int256(lambda) * int256(k)) / 1e18;
            juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;
        }
    }

    function _updateReputation() internal {}

    function _determineWinner(uint256 _disputeId, Vote[] memory allVotes)
        internal
        view
        returns (bool tie, address winner, address loser, uint256 winnerCount, uint256 loserCount)
    {
        Dispute memory d = disputes[_disputeId];
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

    function addJuror(uint256 disputeId) external onlyOwner {
        // Incase there is a tie breaker, this will help in resolving that.
        // This will be called after the first round of selection.
        // Candidate list will get updated here
        // We should penalize the candidates that is forcing us to add more juror.
    }

    function adminParticipateInDispute(uint256 _disputeId) external onlyOwner {
        // To be called by admins
        // Admin is added as candidate. This will be called only after the second round of selection.
        // Admin will be added to the candidate list
    }

    function _updateReputation(uint256 dealId, address juror, bool wonDispute) internal {
        // Code to update juror reputation based on dispute outcome
    }

    function updateMinStakeAmount(uint256 _minStakeAmount) external onlyOwner {
        if (_minStakeAmount == 0) {
            revert JurorManager__ZeroAmount();
        }
        minStakeAmount = _minStakeAmount;
        emit MinStakeAmountUpdated(_minStakeAmount);
    }

    function updateMaxStakeAmount(uint256 _maxStakeAmount) external onlyOwner {
        if (_maxStakeAmount == 0) {
            revert JurorManager__ZeroAmount();
        }
        maxStakeAmount = _maxStakeAmount;
        emit MaxStakeAmountUpdated(_maxStakeAmount);
    }

    // function updateVotingPeriod(uint256 _votingPeriod) external onlyOwner
}
