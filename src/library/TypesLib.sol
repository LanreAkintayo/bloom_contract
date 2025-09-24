//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


library TypesLib {
   enum Status {
        Pending,    // Newly created, waiting
        Acknowledged, // Receiver has acknowledged the deal
        Completed,  // Delivered and claimed successfully
        Disputed,   // Dispute has been raised
        Resolved,   // Dispute settled (either party can get funds)
        Reversed ,   // Funds returned to sender (timeout, cancel)
        Canceled    // Deal canceled by sender before acknowledgment
    }   

    struct Deal {   
        address sender;
        address receiver;
        uint256 amount;
        string description;
        address tokenAddress; // Address(0) for native currency
        Status status;
        uint256 id;
    }


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
    // STRUCTS
    //////////////////////////

    struct Evidence {
        uint256 dealId;
        address uploader;
        string uri;
        uint256 timestamp;
        EvidenceType evidenceType;
        string description;
        bool removed;
    }

    struct Dispute {
        address initiator;
        address sender;
        address receiver;
        address winner;
        string description;
        uint256 dealId;
        uint256 disputeFee;
        address feeTokenAddress;
    }

    struct Juror {
        address jurorAddress;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 score;  
        uint256 missedVotesCount;
        uint256 lastWithdrawn;
    }

    // Keeps track of the stake amount and reputation at selection
    struct Candidate {
        uint256 disputeId;
        address jurorAddress;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 score;
        bool missed;
    }

    struct RequestStatus {
        uint256 paid; // Amount paid in LINK
        bool fulfilled; // Whether request was successfully fulfilled
        uint256[] randomWords;
    }

    struct Vote {
        address jurorAddress;
        uint256 disputeId;
        uint256 dealId;
        address support;
    }

    struct Timer {
        uint256 disputeId;
        uint256 startTime;
        uint256 standardVotingDuration;
        uint256 extendDuration;
    }

    struct PaymentType {
        uint256 disputeId;
        address tokenAddress;
        uint256 amount;
    }


}