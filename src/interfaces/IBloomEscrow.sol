//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


interface IBloomEscrow {
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

    event DealCreated(
        uint256 indexed dealId,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        address tokenAddress
    );

    function createDeal(address receiver, uint256 amount, address tokenAddress) external payable returns (uint256);

    function acknowledgeDeal(uint256 id) external;

    function completeDeal(uint256 id) external;

    function cancelDeal(uint256 id) external;

    function reverseDeal(uint256 id) external;

    function getDeal(uint256 id) external view returns (Deal memory);
}