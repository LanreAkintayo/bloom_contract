//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


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
        address tokenAddress; // Address(0) for native currency
        Status status;
        uint256 id;
    }
}