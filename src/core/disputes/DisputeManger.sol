// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {DisputeStorage} from "./DisputeStorage.sol";
import {console} from "forge-std/Test.sol";
import {TypesLib} from "../../library/TypesLib.sol";

/// @title Dispute Manager for Bloom Escrow
/// @notice Handles disputes and evidence for deals in BloomEscrow
contract DisputeManager is ConfirmedOwner {
    using SafeERC20 for IERC20;
    DisputeStorage public ds;
     IBloomEscrow public bloomEscrow;
    IFeeController public feeController;
    IERC20 public bloomToken;
    address public wrappedNative;

    uint256 public MAX_PERCENT = 10_000;


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
    error DisputeManager__AppealExpired();
    error DisputeManager__AlreadyFinished();
    error DisputeManager__NoReward();
    error DisputeManager__NotEnoughReward();

    //////////////////////////
    // EVENTS
    //////////////////////////

    event DisputeOpened(uint256 indexed dealId, address indexed initiator);
    event EvidenceAdded(
        uint256 indexed dealId,
        address indexed uploader,
        string uri,
        uint128 timestamp,
        TypesLib.EvidenceType evidenceType,
        string description
    );
    event DisputeAppealed(uint256 indexed dealId, uint256 indexed appealId, address indexed participant);
    event DisputeClosed(uint256 indexed _disputeId, address indexed initiator);
    event DisputeFinished(uint256 _disputeId, address winner, address loser, uint256 winnerCount, uint256 loserCount);
    event FundsReleasedToWinner(uint256 _disputeId, address winner);
    event RewardClaimed(address jurorAddress, address tokenAddress, uint256 amount);

    //////////////////////////
    // CONSTRUCTOR
    //////////////////////////

    constructor(address escrowAddress, address feeControllerAddress, address wrappedNativeTokenAddress, address storageAddress)
        ConfirmedOwner(msg.sender)
    {
        bloomEscrow = IBloomEscrow(escrowAddress);
        feeController = IFeeController(feeControllerAddress);
        wrappedNative = wrappedNativeTokenAddress;
        ds = DisputeStorage(storageAddress);
    }

    //////////////////////////
    // EXTERNAL FUNCTIONS
    //////////////////////////

    /// @notice Opens a dispute for a given deal
    /// @param dealId The ID of the deal
    function openDispute(uint256 dealId) external returns (uint256) {
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // You cannot open a dispute if one is already opened for this deal
        // if (disputes[disputeId].initiator != address(0)) {
        //     revert DisputeManager__DisputeAlreadyOpened();
        // }

        // Ensure initiator is sender or receiver
        if (msg.sender != deal.sender && msg.sender != deal.receiver) {
            revert DisputeManager__Restricted();
        }

        if (deal.status != TypesLib.Status.Pending && deal.status != TypesLib.Status.Acknowledged) {
            revert DisputeManager__CannotDispute();
        }

        // Charge dispute fee (if any) - omitted for simplicity
        uint256 disputeFee = 0;

        if (feeController.disputeFeePercentage() > 0) {
            disputeFee = feeController.calculateDisputeFee(deal.amount);
        }

        // Transfer dispute fee to the contract;
        // Dispute fee is the same as the token used to create deal.
        if (deal.tokenAddress != wrappedNative) {
            IERC20 token = IERC20(deal.tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), disputeFee);
        } else {
            (bool native_success,) = msg.sender.call{value: disputeFee}("");
            if (!native_success) {
                revert DisputeManager__TransferFailed();
            }
        }

        // disputeId++;
        uint256 newDisputeId = ds.incrementDisputeId();

        TypesLib.Dispute memory dispute = TypesLib.Dispute({
            initiator: msg.sender,
            sender: deal.sender,
            receiver: deal.receiver,
            winner: address(0),
            dealId: dealId,
            disputeFee: disputeFee,
            feeTokenAddress: deal.tokenAddress
        });

        
        ds.setDisputes(newDisputeId, dispute);

        // disputes[disputeId] = dispute;

        if (ds.dealToDispute(dealId) == 0) {
            ds.setDealToDispute(dealId, newDisputeId);
            // dealToDispute[dealId] = disputeId;
        }

        // update the deal status to Disputed
        bloomEscrow.updateStatus(dealId, TypesLib.Status.Disputed);

        emit DisputeOpened(dealId, msg.sender);
        return newDisputeId;
    }

    function closeDispute(uint256 _disputeId) external {
        TypesLib.Dispute memory dispute = ds.getDispute(_disputeId);

        // Only the initiator can close the dispute
        if (dispute.initiator != msg.sender) {
            revert DisputeManager__NotInitiator();
        }

        // You can only close dispute if jurors are yet to be assigned
        address[] memory disputeJurors = ds.getDisputeJurors(_disputeId);
        if (disputeJurors.length > 0) {
            revert DisputeManager__JurorsAlreadyAssigned();
        }

        ds.updateDisputeWinner(_disputeId, msg.sender);
        // disputeToClose.winner = msg.sender;

        emit DisputeClosed(_disputeId, msg.sender);
    }

    function appeal(uint256 _disputeId) external returns (uint256) {
        uint256[] memory allDisputeAppeals = ds.getDisputeAppeals(_disputeId);

        // Always make use of the last dispute which would represent the last appeal
        uint256 latestId = allDisputeAppeals.length > 0 ? allDisputeAppeals[allDisputeAppeals.length - 1] : _disputeId;

        TypesLib.Dispute memory disputeToAppeal = ds.getDispute(_disputeId);
        uint256 dealId = disputeToAppeal.dealId;
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Increment appeal count by 1;
        uint256 appealCount = ds.incrementAppealCount(_disputeId);
        // appealCounts[_disputeId] += 1;

        // You have to ensure that the dispute has ended;
        TypesLib.Timer memory appealDisputeTimer = ds.getDisputeTimer(latestId);
        
        // Timer memory appealDisputeTimer = disputeTimer[latestId];
        uint256 endTime =
            appealDisputeTimer.startTime + appealDisputeTimer.standardVotingDuration + appealDisputeTimer.extendDuration;
        if (block.timestamp < endTime) {
            revert DisputeManager__NotFinished();
        }

        if (block.timestamp > endTime + ds.appealDuration()) {
            revert DisputeManager__AppealExpired();
        }

        // Make sure that this dispute has not gotten to the maximum appeal allowed
        if (appealCount >= ds.appealThreshold()) {
            revert DisputeManager__MaxAppealExceeded();
        }

        // You have to ensure that you are not the winner of the dispute;
        if (disputeToAppeal.winner == msg.sender) {
            revert DisputeManager__AlreadyWinner();
        }

        // You have to ensure that you have paid for the appeal; Appeal fee will be in stables;
        uint256 appealFee = feeController.calculateAppealFee(deal.tokenAddress, deal.amount, appealCount);

        // Transfer dispute fee to the contract;
        // Dispute fee is the same as the token used to create deal.
        if (deal.tokenAddress != wrappedNative) {
            IERC20 token = IERC20(deal.tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), appealFee);
        } else {
            (bool native_success,) = msg.sender.call{value: appealFee}("");
            if (!native_success) {
                revert DisputeManager__TransferFailed();
            }
        }

        uint256 newDisputeId = ds.incrementDisputeId();

        TypesLib.Dispute memory dispute = TypesLib.Dispute({
            initiator: msg.sender,
            sender: deal.sender,
            receiver: deal.receiver,
            winner: address(0),
            dealId: dealId,
            disputeFee: appealFee,
            feeTokenAddress: deal.tokenAddress
        });

        ds.setDisputes(newDisputeId, dispute);

        // disputes[disputeId] = dispute;

        // Link the dispute Id to the appeal

        ds.pushIntoDisputeAppeals(_disputeId, newDisputeId);
        // disputeAppeals[_disputeId].push(disputeId);

        ds.setAppealToDispute(newDisputeId, _disputeId);
        // appealToDispute[disputeId] = _disputeId; // Appeal id is the disputeId, the _disputeId is passed from the function

        // Emit an event
        emit DisputeAppealed(dealId, newDisputeId, msg.sender);

        return newDisputeId;
    }

    function finishDispute(uint256 _disputeId) external onlyOwner {
        // Check if voting time has elapsed;
        TypesLib.Timer memory appealDisputeTimer = ds.getDisputeTimer(_disputeId);
        TypesLib.Dispute memory disputeToFinish = ds.getDispute(_disputeId);

        if (disputeToFinish.winner != address(0)) {
            revert DisputeManager__AlreadyFinished();
        }

        if (
            block.timestamp
                < appealDisputeTimer.startTime + appealDisputeTimer.standardVotingDuration
                    + appealDisputeTimer.extendDuration
        ) {
            revert DisputeManager__NotFinished();
        }
        TypesLib.Vote[] memory allVotes = ds.getAllDisputeVotes(_disputeId);

        // console.log("Length of all votes: ", allVotes.length);

        // Determine the winner;
        (bool tie, address winner, address loser, uint256 winnerCount, uint256 loserCount) =
            _determineWinner(_disputeId, allVotes);

        // console.log("Tie: ", tie);
        // console.log("Winner: ", winner);
        // console.log("Loser: ", loser);
        // console.log("Winner Count: ", winnerCount);
        // console.log("Loser Count: ", loserCount);

        // Update the reward and reputation accordingly
        _distributeRewardAndReputation(tie, _disputeId, winner, winnerCount);

        // Update all the states
        ds.updateDisputeWinner(_disputeId, winner);
        // disputes[_disputeId].winner = winner;

        // Emit events;
        emit DisputeFinished(_disputeId, winner, loser, winnerCount, loserCount);
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

    function _distributeRewardAndReputation(bool tie, uint256 _disputeId, address winner, uint256 winnerCount)
        internal
    {
        if (tie) return;

        uint256 totalAmountSlashed;
        uint256 totalWinnerStakedAmount;
        address[] memory selectedJurors = ds.getDisputeJurors(_disputeId); 
        address[] memory winnersAlone = new address[](winnerCount);
        uint256 winnerId = 0;
        uint256 votedJurorCount = 0;
        TypesLib.Dispute memory currentDispute = ds.getDispute(_disputeId); 
        uint256 baseFee = (ds.basePercentage() * currentDispute.disputeFee) / MAX_PERCENT;

        // Calculate the total amount slashed from the losers
        for (uint256 i = 0; i < selectedJurors.length; i++) {
            // Make sure you deal with only the jurors that voted;
            TypesLib.Candidate memory currentCandidate = ds.getDisputeCandidate(_disputeId, selectedJurors[i]);
            address currentJurorAddress = currentCandidate.jurorAddress;
            uint256 currentStakeAmount = currentCandidate.stakeAmount;
            Vote memory currentVote = disputeVotes[_disputeId][currentJurorAddress];

            console.log(
                "ongoing dispute count of ", currentJurorAddress, " is ", ongoingDisputeCount[currentJurorAddress]
            );

            if (currentJurorAddress != owner()) {
                ongoingDisputeCount[currentJurorAddress] -= 1;
            }

            if (currentVote.support != address(0)) {
                votedJurorCount++;

                // Share the base fee to all the voted jurors;
                jurorTokenPayments[currentJurorAddress][currentDispute.feeTokenAddress] += baseFee;

                // Insider here, they vote either for the winner or for the loser;
                // uint256 base
                if (currentVote.support != winner) {
                    // Update the disputeJurorPayment
                    disputeToJurorPayment[_disputeId][currentJurorAddress] = PaymentType({
                        disputeId: _disputeId,
                        tokenAddress: currentDispute.feeTokenAddress,
                        amount: baseFee
                    });

                    uint256 amountDeducted = (currentStakeAmount * slashPercentage) / MAX_PERCENT;
                    totalAmountSlashed += amountDeducted;

                    // console.log("amount deducted: ", amountDeducted);

                    if (currentCandidate.jurorAddress != owner()) {
                        Juror storage juror = jurors[currentJurorAddress];
                        // Update juror stake amount
                        juror.stakeAmount -= amountDeducted;

                        // Update the juror reputation;
                        uint256 oldReputation = juror.reputation;
                        int256 newReputation = int256(oldReputation) - (int256(lambda) * int256(k)) / 1e18;

                        // console.log("new reputation: ", newReputation);

                        juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;

                        // console.log("Juror reputation: ", juror.reputation);

                        // We don't need to update the Candidate struct because it is only used to note the staked value as at when selected to vote.
                    }
                } else {
                    totalWinnerStakedAmount += currentCandidate.stakeAmount;
                    winnersAlone[winnerId++] = (currentCandidate.jurorAddress);
                }
            } else {
                // The candidates here did not vote at all but they were chosen

                // console.log("Will it ever enter here");

                uint256 deductedAmount = currentStakeAmount * noVoteSlashPercentage / MAX_PERCENT;
                Juror storage juror = jurors[currentJurorAddress];
                juror.stakeAmount -= deductedAmount;

                // console.log("deductedAmount: ", deductedAmount);
                // console.log("juror.stakeAmount: ", juror.stakeAmount);

                // Update the juror reputation;
                uint256 oldReputation = juror.reputation;
                int256 newReputation = int256(oldReputation) - (int256(lambda) * int256(noVoteK)) / 1e18;

                // console.log("New reputation: ", newReputation);

                juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;

                // console.log("Juror reputation: ", juror.reputation);

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
        // Update their payments;
        uint256 remainingPercent = MAX_PERCENT - (basePercentage * votedJurorCount);
        uint256 remainingFee = remainingPercent * currentDispute.disputeFee / MAX_PERCENT;
        uint256 individualFee = remainingFee / winnersAlone.length;
        uint256 accumulatedFee = 0;

        for (uint256 i = 0; i < winnersAlone.length; i++) {
            // console.log("Distributing to winner");
            address currentAddress = winnersAlone[i];
            Candidate memory currentCandidate = isDisputeCandidate[_disputeId][currentAddress];

            uint256 rewardAmount = (currentCandidate.stakeAmount * totalAmountSlashed) / totalWinnerStakedAmount;

            Juror storage juror = jurors[currentAddress];
            juror.stakeAmount += rewardAmount;

            // Update the reputation
            uint256 oldReputation = juror.reputation;
            int256 newReputation = int256(oldReputation) + (int256(lambda) * int256(k)) / 1e18;
            juror.reputation = newReputation > 0 ? uint256(newReputation) : 0;

            bool isPresent = isInActiveJurorAddresses(currentAddress);

            // // Share the base fee to all the voted jurors;
            jurorTokenPayments[currentAddress][currentDispute.feeTokenAddress] += individualFee;

            // Update the disputeJurorPayment
            disputeToJurorPayment[_disputeId][currentAddress] = PaymentType({
                disputeId: _disputeId,
                tokenAddress: currentDispute.feeTokenAddress,
                amount: baseFee + individualFee
            });

            accumulatedFee += individualFee;

            if (ongoingDisputeCount[currentAddress] <= ongoingDisputeThreshold && !isPresent) {
                // Push back to the array of activeJurorAddresses
                _pushToActiveJurorAddresses(currentAddress);
            }
        }

        if (remainingFee > accumulatedFee) {
            uint256 residues = remainingFee - accumulatedFee;
            residuePayments[_disputeId][currentDispute.feeTokenAddress] += residues;
            totalResidue[currentDispute.feeTokenAddress] += residues;
        }
    }

    function releaseFundsToWinner(uint256 _disputeId) external {
        // Wait for 24 hours to see whether there will be appeal
        uint256[] memory allDisputeAppeals = disputeAppeals[_disputeId];

        // Always make use of the last dispute which would represent the last appeal
        uint256 latestId = allDisputeAppeals.length > 0 ? allDisputeAppeals[allDisputeAppeals.length - 1] : _disputeId;

        Dispute memory latestDispute = disputes[latestId];

        uint256 dealId = latestDispute.dealId;

        Timer memory latestDisputeTimer = disputeTimer[latestId];
        uint256 endTime =
            latestDisputeTimer.startTime + latestDisputeTimer.standardVotingDuration + latestDisputeTimer.extendDuration;

        if (block.timestamp < endTime + appealDuration) {
            revert DisputeManager__AppealTime();
        }

        // Make sure that this is called by the winner of the dispute
        if (latestDispute.winner != msg.sender) {
            revert DisputeManager__OnlyWinner();
        }

        // Relase the funds to the winner
        bloomEscrow.releaseFunds(latestDispute.winner, dealId);
        emit FundsReleasedToWinner(_disputeId, msg.sender);
    }

    function claimReward(address tokenAddress, uint256 amount) external {
        uint256 reward = jurorTokenPayments[msg.sender][tokenAddress];
        uint256 rewardClaimed = jurorTokenPaymentsClaimed[msg.sender][tokenAddress];
        uint256 amountAvailable = reward - rewardClaimed;

        if (reward <= 0) {
            revert DisputeManager__NoReward();
        }

        if (amountAvailable < amount) {
            revert DisputeManager__NotEnoughReward();
        }

        if (tokenAddress == wrappedNative) {
            (bool native_success,) = msg.sender.call{value: amount}("");
            if (!native_success) {
                revert DisputeManager__TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        }

        // jurorTokenPaymentsClaimed[msg.sender][tokenAddress] += amount;

        emit RewardClaimed(msg.sender, tokenAddress, amount);
    }

    /// @notice Adds evidence to a dispute
    /// @param dealId The ID of the deal
    /// @param uri The URI of the evidence (IPFS or similar)
    /// @param evidenceType The type of evidence
    /// @param description Additional description of the evidence
    function addEvidence(uint256 dealId, string calldata uri, TypesLib.EvidenceType evidenceType, string calldata description)
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

    // @complete. This is not nice like this. It's just for testing
    function changeCallbackGasLimit(uint32 _callbackGasLimit) external onlyOwner {
        callbackGasLimit = _callbackGasLimit;

    }

    function getDispute(uint256 _disputeId) external view returns (TypesLib.Dispute memory) {
        return disputes[_disputeId];
    }

    function getDisputeCandidate(uint256 _disputeId, address _jurorAddress) external view returns (TypesLib.Candidate memory) {
        return isDisputeCandidate[_disputeId][_jurorAddress];
    }

    function getDisputeVote(uint256 _disputeId, address _jurorAddress) external view returns (TypesLib.Vote memory) {
        return disputeVotes[_disputeId][_jurorAddress];
    }

    function getDisputeVotes(uint256 _disputeId) external view returns (TypesLib.Vote[] memory) {
        return allDisputeVotes[_disputeId];
    }

    function getDisputeTimer(uint256 _disputeId) external view returns (TypesLib.Timer memory) {
        return disputeTimer[_disputeId];
    }

    function getDisputeAppeals(uint256 _disputeId) external view returns (uint256[] memory) {
        return disputeAppeals[_disputeId];
    }

    function getDisputeAppealCount(uint256 _disputeId) external view returns (uint256) {
        return appealCounts[_disputeId];
    }
}
