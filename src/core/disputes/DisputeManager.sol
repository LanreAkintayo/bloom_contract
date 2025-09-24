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
import {JurorManager} from "./JurorManager.sol";

/// @title Dispute Manager for Bloom Escrow
/// @notice Handles disputes and evidence for deals in BloomEscrow
contract DisputeManager is ConfirmedOwner {
    using SafeERC20 for IERC20;

    DisputeStorage public ds;
    IBloomEscrow public bloomEscrow;
    IFeeController public feeController;
    IERC20 public bloomToken;
    JurorManager public jurorManager;

    uint256 public constant MAX_PERCENT = 10_000;

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
    error DisputeManager__DisputeNotEnded();

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
    event AdminParticipatedInDispute(uint256 indexed _disputeId, address indexed support);

    //////////////////////////
    // CONSTRUCTOR
    //////////////////////////

    constructor(address storageAddress) ConfirmedOwner(msg.sender) {
        ds = DisputeStorage(storageAddress);
        bloomEscrow = ds.getBloomEscrow();
        feeController = ds.getFeeController();
        bloomToken = ds.getBloomToken();
    }

    //////////////////////////
    // EXTERNAL FUNCTIONS
    //////////////////////////

    /// @notice Opens a dispute for a given deal
    /// @param dealId The ID of the deal
    function openDispute(uint256 dealId, string calldata description) external returns (uint256, uint256) {
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
        if (deal.tokenAddress != ds.wrappedNative()) {
            IERC20 token = IERC20(deal.tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), disputeFee);
        } else {
            (bool nativeSuccess,) = msg.sender.call{value: disputeFee}("");
            if (!nativeSuccess) {
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
            description: description,
            dealId: dealId,
            disputeFee: disputeFee,
            feeTokenAddress: deal.tokenAddress
        });

        ds.setDisputes(newDisputeId, dispute);

        ds.updateAllDisputes(newDisputeId);

        // disputes[disputeId] = dispute;

        if (ds.dealToDispute(dealId) == 0) {
            ds.setDealToDispute(dealId, newDisputeId);
            // dealToDispute[dealId] = disputeId;
        }

        // update the deal status to Disputed
        bloomEscrow.updateStatus(dealId, TypesLib.Status.Disputed);

        // Select jurors;
        uint256 requestId = jurorManager.selectJurors(newDisputeId);

        console.log("Request ID: ", requestId);

        emit DisputeOpened(dealId, msg.sender);
        return (newDisputeId, requestId);
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

    function appeal(uint256 _disputeId, string calldata description) external returns (uint256, uint256) {
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
        
        if (ds.tieBreakerJuror(latestId) != address(0)){
            endTime += ds.tieBreakingDuration();
        }

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
        if (deal.tokenAddress != ds.wrappedNative()) {
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
            description: description,
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

        // Select Jurors;
         // Select jurors;
        uint256 requestId = jurorManager.selectJurors(newDisputeId);

        // Emit an event
        emit DisputeAppealed(dealId, newDisputeId, msg.sender);

        return (newDisputeId, requestId);
    }

    function releaseFundsToWinner(uint256 _disputeId) external {
        // Wait for 24 hours to see whether there will be appeal
        uint256[] memory allDisputeAppeals = ds.getDisputeAppeals(_disputeId); // disputeAppeals[_disputeId];

        // Always make use of the last dispute which would represent the last appeal
        uint256 latestId = allDisputeAppeals.length > 0 ? allDisputeAppeals[allDisputeAppeals.length - 1] : _disputeId;

        TypesLib.Dispute memory latestDispute = ds.getDispute(latestId); // disputes[latestId];

        uint256 dealId = latestDispute.dealId;

        TypesLib.Timer memory latestDisputeTimer = ds.getDisputeTimer(latestId); // disputeTimer[latestId];
        uint256 endTime =
            latestDisputeTimer.startTime + latestDisputeTimer.standardVotingDuration + latestDisputeTimer.extendDuration;

        if (block.timestamp < endTime + ds.appealDuration()) {
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
        uint256 reward = ds.getJurorTokenPayment(msg.sender, tokenAddress); // jurorTokenPayments[msg.sender][tokenAddress];

        uint256 rewardClaimed = ds.jurorTokenPaymentsClaimed(msg.sender, tokenAddress); //  jurorTokenPaymentsClaimed[msg.sender][tokenAddress];
        uint256 amountAvailable = reward - rewardClaimed;

        if (reward <= 0) {
            revert DisputeManager__NoReward();
        }

        if (amountAvailable < amount) {
            revert DisputeManager__NotEnoughReward();
        }

        if (tokenAddress == ds.wrappedNative()) {
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
    function addEvidence(
        uint256 dealId,
        string calldata uri,
        TypesLib.EvidenceType evidenceType,
        string calldata description
    ) external {
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
        TypesLib.Evidence memory evidence = TypesLib.Evidence({
            dealId: dealId,
            uploader: msg.sender,
            uri: uri,
            timestamp: timestamp,
            evidenceType: evidenceType,
            description: description,
            removed: false
        });

        ds.pushIntoDealEvidences(dealId, msg.sender, evidence);
        // dealEvidences[dealId][msg.sender].push(evidence);

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

        TypesLib.Evidence[] memory evidences = ds.getDealEvidence(dealId, msg.sender); //dealEvidences(dealId, msg.sender); // dealEvidences[dealId][msg.sender];

        if (evidenceIndex >= evidences.length) {
            revert DisputeManager__CannotAddEvidence();
        }

        ds.removeEvidence(evidenceIndex, dealId, msg.sender);

        // evidences[evidenceIndex].removed = true;

        // Note: No event emitted for evidence removal to maintain evidence integrity
    }

    function _popFromActiveJurorAddresses(address jurorAddress) internal {
        ds.popFromActiveJurorAddresses(jurorAddress);
    }

    function _pushToActiveJurorAddresses(address jurorAddress) internal {
        ds.pushToActiveJurorAddresses(jurorAddress);
    }

    function isInActiveJurorAddresses(address _jurorAddress) internal view returns (bool) {
        // return ds.activeJurorAddresses(jurorAddressIndex(_jurorAddress))
        return ds.isInActiveJurorAddresses(_jurorAddress);
    }

    function addJurorManager(address jurorManagerAddress) external onlyOwner {
        jurorManager = JurorManager(jurorManagerAddress);
    }
}
