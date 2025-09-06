// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import {DisputeStorage} from "./DisputeStorage.sol";

/// @title Dispute Manager for Bloom Escrow
/// @notice Handles disputes and evidence for deals in BloomEscrow
abstract contract DisputeManager is DisputeStorage, ConfirmedOwner {
    using SafeERC20 for IERC20;

    //////////////////////////
    // ERRORS
    //////////////////////////
    error DisputeManager__CannotDispute();
    error DisputeManager__CannotAddEvidence();
    error DisputeManager__NotParticipant();
    error DisputeManager__DisputeAlreadyOpened();
    error DisputeManager__Restricted();
    error DisputeManager__NotDisputed();
    error DisputeManager__TransferFailed();
    error DisputeManager__NotFinished();
    error DisputeManager__MaxAppealExceeded();
    error DisputeManager__AlreadyWinner();
    error DisputeManager__JurorsAlreadyAssigned();
    error DisputeManager__NotInitiator();
    error DisputeManager__AppealTime();
    error DisputeManager__OnlyWinner();

    //////////////////////////
    // EVENTS
    //////////////////////////

    event DisputeOpened(uint256 indexed dealId, address indexed initiator);
    event EvidenceAdded(
        uint256 indexed dealId,
        address indexed uploader,
        string uri,
        uint128 timestamp,
        EvidenceType evidenceType,
        string description
    );
    event DisputeAppealed(uint256 indexed dealId, address indexed participant);
    event DisputeClosed(uint256 indexed _disputeId, address indexed initiator);
    event DisputeFinished(uint256 _disputeId, address winner, address loser, uint256 winnerCount, uint256 loserCount);
    event FundsReleasedToWinner(uint256 _disputeId, address winner);


    //////////////////////////
    // CONSTRUCTOR
    //////////////////////////

    constructor(address escrowAddress, address feeControllerAddress) ConfirmedOwner(msg.sender) {
        bloomEscrow = IBloomEscrow(escrowAddress);
        feeController = IFeeController(feeControllerAddress);
    }

    //////////////////////////
    // EXTERNAL FUNCTIONS
    //////////////////////////

    /// @notice Opens a dispute for a given deal
    /// @param dealId The ID of the deal
    function openDispute(uint256 dealId) external {
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // You cannot open a dispute if one is already opened for this deal
        if (disputes[disputeId].initiator != address(0)) {
            revert DisputeManager__DisputeAlreadyOpened();
        }

        // Ensure initiator is sender or receiver
        if (msg.sender != deal.sender && msg.sender != deal.receiver) {
            revert DisputeManager__Restricted();
        }

        if (deal.status != TypesLib.Status.Pending && deal.status != TypesLib.Status.Acknowledged) {
            revert DisputeManager__CannotDispute();
        }

        Dispute memory dispute = Dispute({
            dealId: dealId,
            initiator: msg.sender,
            sender: deal.sender,
            receiver: deal.receiver,
            winner: address(0)
        });

        disputes[disputeId] = dispute;
        dealToDispute[dealId] = disputeId;
        disputeId++;

        // Charge dispute fee (if any) - omitted for simplicity
        uint256 disputeFee = 0;

        if (feeController.disputeFeePercentage() > 0) {
            disputeFee = feeController.calculateDisputeFee(deal.amount);
        }

        // Transfer dispute fee to the contract;
        // Dispute fee is the same as the token used to create deal.
        if (deal.tokenAddress != address(0)) {
            IERC20 token = IERC20(deal.tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), disputeFee);
        } else {
            (bool native_success,) = msg.sender.call{value: disputeFee}("");
            if (!native_success) {
                revert DisputeManager__TransferFailed();
            }
        }

        // update the deal status to Disputed
        bloomEscrow.updateStatus(dealId, TypesLib.Status.Disputed);

        emit DisputeOpened(dealId, msg.sender);
    }

    function closeDispute(uint256 _disputeId) external {
        Dispute storage disputeToClose = disputes[_disputeId];

        // Only the initiator can close the dispute
        if (disputeToClose.initiator != msg.sender) {
            revert DisputeManager__NotInitiator();
        }

        // You can only close dispute if jurors are yet to be assigned
        if (disputeJurors[_disputeId].length > 0) {
            revert DisputeManager__JurorsAlreadyAssigned();
        }

        disputeToClose.winner = msg.sender;

        emit DisputeClosed(_disputeId, msg.sender);
    }

    function appeal(uint256 _disputeId) external {
        Dispute memory disputeToAppeal = disputes[_disputeId];
        uint256 dealId = disputeToAppeal.dealId;
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Increment appeal count by 1;
        appealCounts[_disputeId] += 1;

        // You have to ensure that the dispute has ended;
        Timer memory appealDisputeTimer = disputeTimer[_disputeId];
        if (
            block.timestamp
                < appealDisputeTimer.startTime + appealDisputeTimer.standardVotingDuration
                    + appealDisputeTimer.extendDuration
        ) {
            revert DisputeManager__NotFinished();
        }

        // Make sure that this dispute has not gotten to the maximum appeal allowed
        if (appealCounts[_disputeId] >= appealThreshold) {
            revert DisputeManager__MaxAppealExceeded();
        }

        // You have to ensure that you are not the winner of the dispute;
        if (disputeToAppeal.winner == msg.sender) {
            revert DisputeManager__AlreadyWinner();
        }

        // You have to ensure that you have paid for the appeal; Appeal fee will be in stables;
        uint256 appealFee = feeController.calculateAppealFee(deal.tokenAddress, deal.amount, appealCounts[_disputeId]);

        // Transfer dispute fee to the contract;
        // Dispute fee is the same as the token used to create deal.
        if (deal.tokenAddress != address(0)) {
            IERC20 token = IERC20(deal.tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), appealFee);
        } else {
            (bool native_success,) = msg.sender.call{value: appealFee}("");
            if (!native_success) {
                revert DisputeManager__TransferFailed();
            }
        }

        // Link the dispute Id to the appeal
        disputeAppeals[_disputeId].push(disputeId);
        disputeId++;

        emit DisputeAppealed(dealId, msg.sender);

        // Emit an event
    }

    function finishDispute(uint256 _disputeId) external onlyOwner {
        // Check if voting time has elapsed;
        Timer memory appealDisputeTimer = disputeTimer[_disputeId];

        if (
            block.timestamp
                < appealDisputeTimer.startTime + appealDisputeTimer.standardVotingDuration
                    + appealDisputeTimer.extendDuration
        ) {
            revert DisputeManager__NotFinished();
        }
        Vote[] memory allVotes = allDisputeVotes[_disputeId];

        // Determine the winner;
        (bool tie, address winner, address loser, uint256 winnerCount, uint256 loserCount) =
            _determineWinner(_disputeId, allVotes);

        // Update the reward and reputation accordingly
        _distributeRewardAndReputation(tie, _disputeId, winner, winnerCount);

        // Update all the states
        disputes[_disputeId].winner = winner;

        // Emit events;
        emit DisputeFinished(_disputeId, winner, loser, winnerCount, loserCount);
    }

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

    function _distributeRewardAndReputation(bool tie, uint256 _disputeId, address winner, uint256 winnerCount)
        internal
    {
        if (tie) return;

        uint256 totalAmountSlashed;
        uint256 totalWinnerStakedAmount;
        address[] memory selectedJurors = disputeJurors[_disputeId];
        address[] memory winnersAlone = new address[](winnerCount);
        uint256 winnerId = 0;

        // Calculate the total amount slashed from the losers
        for (uint256 i = 0; i < selectedJurors.length; i++) {
            // Make sure you deal with only the jurors that voted;
            Candidate memory currentCandidate = isDisputeCandidate[_disputeId][selectedJurors[i]];
            address currentJurorAddress = currentCandidate.jurorAddress;
            uint256 currentStakeAmount = currentCandidate.stakeAmount;
            Vote memory currentVote = disputeVotes[_disputeId][currentJurorAddress];

            ongoingDisputeCount[currentJurorAddress] -= 1;

            if (currentVote.support != address(0)) {
                if (currentVote.support != winner) {
                    uint256 amountDeducted = (currentStakeAmount * slashPercentage) / MAX_PERCENT;
                    totalAmountSlashed += amountDeducted;

                    if (currentCandidate.jurorAddress != owner()) {
                        Juror storage juror = jurors[currentJurorAddress];
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
                    winnersAlone[winnerId++] = (currentCandidate.jurorAddress);
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
                Candidate storage candidate = isDisputeCandidate[_disputeId][currentJurorAddress];

                // Set to missed if it is not set yet.
                if (!candidate.missed) {
                    candidate.missed = true;
                    juror.missedVotesCount += 1;

                    if (juror.missedVotesCount > missedVoteThreshold) {
                        _popFromActiveJurorAddresses(currentJurorAddress);
                    }
                }
            }
        }

        // Let's distribute to the winners;
        for (uint256 i = 0; i < winnersAlone.length; i++) {
            address currentAddress = winnersAlone[i];
            Candidate memory currentCandidate = isDisputeCandidate[_disputeId][currentAddress];

            uint256 rewardAmount = (currentCandidate.stakeAmount * totalAmountSlashed) / totalWinnerStakedAmount;

            Juror storage juror = jurors[currentAddress];
            juror.stakeAmount += rewardAmount;

            // Update the reputation
            uint256 oldReputation = juror.reputation;
            int256 newReputation = int256(oldReputation) + (int256(lambda) * int256(k)) / 1e18;
            juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;

            ongoingDisputeCount[currentAddress] -= 1;
            bool isPresent = isInActiveJurorAddresses(currentAddress);

            if (ongoingDisputeCount[currentAddress] <= ongoingDisputeThreshold && !isPresent) {
                // Push back to the array of activeJurorAddresses
                _pushToActiveJurorAddresses(currentAddress);
            }
        }
    }

    function releaseFundsToWinner(uint256 _disputeId) external {
        // Wait for 24 hours to see whether there will be appeal
        uint256[] memory allDisputeAppeals = disputeAppeals[_disputeId];

        // Always make use of the last dispute which would represent the last appeal
        uint256 latestId = allDisputeAppeals.length > 0 ? _disputeId : allDisputeAppeals[allDisputeAppeals.length - 1];
        Dispute memory latestDispute = disputes[latestId];
        uint256 dealId = latestDispute.dealId;
       
        Timer memory latestDisputeTimer = disputeTimer[latestId];
        uint256 endTime = latestDisputeTimer.startTime + latestDisputeTimer.standardVotingDuration + latestDisputeTimer.extendDuration;

        if (block.timestamp < endTime + appealDuration){
            revert DisputeManager__AppealTime();
        }

        // Make sure that this is called by the winner of the dispute
        if (latestDispute.winner != msg.sender){
            revert DisputeManager__OnlyWinner();
        }

        // Relase the funds to the winner
        bloomEscrow.releaseFunds(latestDispute.winner, dealId);
        emit FundsReleasedToWinner(_disputeId, msg.sender);
    }

    /// @notice Adds evidence to a dispute
    /// @param dealId The ID of the deal
    /// @param uri The URI of the evidence (IPFS or similar)
    /// @param evidenceType The type of evidence
    /// @param description Additional description of the evidence
    function addEvidence(uint256 dealId, string calldata uri, EvidenceType evidenceType, string calldata description)
        external
    {
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Ensure deal is currently disputed
        if (deal.status != TypesLib.Status.Disputed) {
            revert DisputeManager__CannotAddEvidence();
        }

        // Ensure uploader is sender or receiver
        if (msg.sender != deal.sender && msg.sender != deal.receiver) {
            revert DisputeManager__NotParticipant();
        }
        uint128 timestamp = uint128(block.timestamp);
        Evidence memory evidence = Evidence({
            dealId: dealId,
            uploader: msg.sender,
            uri: uri,
            timestamp: timestamp,
            evidenceType: evidenceType,
            description: description,
            removed: false
        });

        dealEvidences[dealId][msg.sender].push(evidence);

        emit EvidenceAdded(dealId, msg.sender, uri, timestamp, evidenceType, description);
    }

    function removeEvidence(uint256 dealId, uint256 evidenceIndex) external {
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Ensure deal is currently disputed
        if (deal.status != TypesLib.Status.Disputed) {
            revert DisputeManager__NotDisputed();
        }

        // Ensure uploader is sender or receiver
        if (msg.sender != deal.sender && msg.sender != deal.receiver) {
            revert DisputeManager__NotParticipant();
        }

        Evidence[] storage evidences = dealEvidences[dealId][msg.sender];

        if (evidenceIndex >= evidences.length) {
            revert DisputeManager__CannotAddEvidence();
        }

        evidences[evidenceIndex].removed = true;

        // Note: No event emitted for evidence removal to maintain evidence integrity
    }

    function _popFromActiveJurorAddresses(address jurorAddress) internal {
        uint256 lastJurorIndex = activeJurorAddresses.length - 1;
        uint256 currentJurorIndex = jurorAddressIndex[jurorAddress];

        if (currentJurorIndex != lastJurorIndex) {
            address lastJurorAddress = activeJurorAddresses[activeJurorAddresses.length - 1];

            activeJurorAddresses[currentJurorIndex] = lastJurorAddress;
            jurorAddressIndex[lastJurorAddress] = currentJurorIndex;
        }

        // Pop the juror address
        activeJurorAddresses.pop();

        // Clean up mapping
        delete jurorAddressIndex[jurorAddress];
    }

    function _pushToActiveJurorAddresses(address jurorAddress) internal {
        // Add a new fresh juror to the activejurorAddresses
        jurorAddressIndex[jurorAddress] = activeJurorAddresses.length;
        activeJurorAddresses.push(jurorAddress);
    }

    function isInActiveJurorAddresses(address _jurorAddress) internal view returns (bool) {
        return activeJurorAddresses[jurorAddressIndex[_jurorAddress]] == _jurorAddress;
    }

      function getDisputeCandidate(uint256 _disputeId, address _jurorAddress) external view returns (Candidate memory) {
        return isDisputeCandidate[_disputeId][_jurorAddress];
    }

    function getDisputeVote(uint256 _disputeId, address _jurorAddress) external view returns (Vote memory) {
        return disputeVotes[_disputeId][_jurorAddress];
    }

    function getDisputeVotes(uint256 _disputeId) external view returns (Vote[] memory) {
        return allDisputeVotes[_disputeId];
    }

    function getDisputeTimer(uint256 _disputeId) external view returns (Timer memory) {
        return disputeTimer[_disputeId];
    }

    function getDisputeAppeals(uint256 _disputeId) external view returns (uint256[] memory) {
        return disputeAppeals[_disputeId];
    }

    function getDisputeAppealCount(uint256 _disputeId) external view returns (uint256) {
        return appealCounts[_disputeId];
    }
}
