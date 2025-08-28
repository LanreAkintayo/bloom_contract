//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

contract DisputeManager {

    enum EvidenceType{
        TEXT,
        IMAGE,
        VIDEO,
        AUDIO,
        DOCUMENT
    }

    struct Evidence{
        address uploader;
        string uri;
        uint256 timestamp;
        EvidenceType evidenceType;
        string description;
    }


    // struct Dispute {
    //     uint256 dealId;
    //     address initiator;
    //     Evidence 
    //     bool resolved;
    // }

    // mapping(uint256 => Dispute) public disputes;

    function openDispute(uint256 dealId, address initiator, string memory reason) external {

    }
}