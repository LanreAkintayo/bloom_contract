//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IBloomEscrow} from "../interfaces/IBloomEscrow.sol";

contract DisputeManager {

    error DisputeManager__CannotDispute();
    error BloomEscrow__CannotAddEvidence();
    error BloomEscrow__NotParticipant();

    event DisputeOpened(uint256 indexed dealId, address indexed initiator);

    enum EvidenceType{
        TEXT,
        IMAGE,
        VIDEO,
        AUDIO,
        DOCUMENT
    }

    struct Evidence{
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

    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => mapping(address => Evidence[])) public dealEvidences; 
    uint256 public disputeId;
    IBloomEscrow public bloomEscrow;

    constructor (address escrowAddress) {
        bloomEscrow = IBloomEscrow(escrowAddress);
    }
    

    function openDispute(uint256 dealId, address initiator) external {

        // Ensure that initiator is the creator of the deal (sender)

        if (disputes[disputeId].initiator != address(0)) {
            revert DisputeManager__CannotDispute();
        }

        Dispute memory dispute;
        dispute.dealId = dealId;
        dispute.initiator = initiator;

        disputes[disputeId] = dispute;
        disputeId++;

        emit DisputeOpened(dealId, initiator);

    }

    function addEvidence(uint256 dealId, address uploader, string calldata uri, uint128 timestamp, EvidenceType evidenceType, string calldata description ) external{

        IBloomEscrow.Deal memory deal = bloomEscrow.getDeal(dealId);
        
        // Ensure that the deal is currently in a disputed state
        if (deal.status != IBloomEscrow.Status.Disputed) {
            revert BloomEscrow__CannotAddEvidence();
        }
        // Ensure that the uploader is either the sender or receiver of the deal
        if (uploader != deal.sender && uploader != deal.receiver) {
            revert BloomEscrow__NotParticipant();
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
     

    }
}