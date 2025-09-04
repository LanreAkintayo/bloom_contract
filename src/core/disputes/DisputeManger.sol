// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";

import {DisputeStorage} from "./DisputeStorage.sol";

/// @title Dispute Manager for Bloom Escrow
/// @notice Handles disputes and evidence for deals in BloomEscrow
abstract contract DisputeManager is DisputeStorage {

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


    //////////////////////////
    // CONSTRUCTOR
    //////////////////////////

    constructor(address escrowAddress, address feeControllerAddress) {
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

        Dispute memory dispute = Dispute({dealId: dealId, initiator: msg.sender, sender: deal.sender, receiver: deal.receiver, winner: address(0)});

        disputes[disputeId] = dispute;
        disputeId++;

        // Charge dispute fee (if any) - omitted for simplicity
        uint256 disputeFee = 0;

        if (feeController.disputeFee() > 0) {
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

        disputeId++;
        disputeAppeals[_disputeId].push(disputeId);


        // Link the dispute Id to the appeal

        // Emit an event
    }


    /// @notice Adds evidence to a dispute
    /// @param dealId The ID of the deal
    /// @param uri The URI of the evidence (IPFS or similar)
    /// @param evidenceType The type of evidence
    /// @param description Additional description of the evidence
    function addEvidence(
        uint256 dealId,
        string calldata uri,
        EvidenceType evidenceType,
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

}
