// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IBloomEscrow} from "../interfaces/IBloomEscrow.sol";
import {TypesLib} from "../library/TypesLib.sol";

/// @title Dispute Manager for Bloom Escrow
/// @notice Handles disputes and evidence for deals in BloomEscrow
contract DisputeManager {
    //////////////////////////
    // ENUMS
    //////////////////////////

    enum EvidenceType {
        TEXT,
        IMAGE,
        VIDEO,
        AUDIO,
        DOCUMENT
    }

    //////////////////////////
    // ERRORS
    //////////////////////////

    error DisputeManager__CannotDispute();
    error DisputeManager__CannotAddEvidence();
    error DisputeManager__NotParticipant();
    error DisputeManager__DisputeAlreadyOpened();
    error DisputeManager__Restricted();
    error DisputeManager__NotDisputed();

    //////////////////////////
    // EVENTS
    //////////////////////////

    event DisputeOpened(uint256 indexed dealId, address indexed initiator);
    event EvidenceAdded(
        uint256 indexed dealId,
        address indexed uploader,
        string uri,
        uint256 timestamp,
        EvidenceType evidenceType,
        string description
    );

    //////////////////////////
    // STRUCTS
    //////////////////////////

    struct Evidence {
        uint256 dealId;
        address uploader;
        string uri;
        uint256 timestamp;
        EvidenceType evidenceType;
        string description;
    }

    struct Dispute {
        uint256 dealId;
        address initiator;
        address winner;
    }

    //////////////////////////
    // STATE VARIABLES
    //////////////////////////

    IBloomEscrow public bloomEscrow;

    uint256 public disputeId;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => mapping(address => Evidence[])) public dealEvidences;

    //////////////////////////
    // CONSTRUCTOR
    //////////////////////////

    constructor(address escrowAddress) {
        bloomEscrow = IBloomEscrow(escrowAddress);
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

        Dispute memory dispute = Dispute({dealId: dealId, initiator: msg.sender, winner: address(0)});

        disputes[disputeId] = dispute;
        disputeId++;

        // update the deal status to Disputed
        bloomEscrow.updateStatus(dealId, TypesLib.Status.Disputed);


        emit DisputeOpened(dealId, msg.sender);
    }

    /// @notice Adds evidence to a dispute
    /// @param dealId The ID of the deal
    /// @param uploader The participant adding the evidence
    /// @param uri The URI of the evidence (IPFS or similar)
    /// @param timestamp The timestamp of the evidence
    /// @param evidenceType The type of evidence
    /// @param description Additional description of the evidence
    function addEvidence(
        uint256 dealId,
        address uploader,
        string calldata uri,
        uint128 timestamp,
        EvidenceType evidenceType,
        string calldata description
    ) external {
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Ensure deal is currently disputed
        if (deal.status != TypesLib.Status.Disputed) {
            revert DisputeManager__CannotAddEvidence();
        }

        // Ensure uploader is sender or receiver
        if (uploader != deal.sender && uploader != deal.receiver) {
            revert DisputeManager__NotParticipant();
        }

        Evidence memory evidence = Evidence({
            dealId: dealId,
            uploader: uploader,
            uri: uri,
            timestamp: timestamp,
            evidenceType: evidenceType,
            description: description
        });

        dealEvidences[dealId][uploader].push(evidence);

        emit EvidenceAdded(dealId, uploader, uri, timestamp, evidenceType, description);
    }
}
