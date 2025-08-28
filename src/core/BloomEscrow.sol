// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error BloomEscrow__InvalidParameters();
error BloomEscrow__TransferFailed();
error BloomEscrow__NotSender();
error BloomEscrow__NotPending();
error BloomEscrow__NotReceiver();
error BloomEscrow__NotAcknowledged();
error BloomEscrow__AlreadyAcknowledged();
error BloomEscrow__Restricted();
error BloomEscrow__CannotDispute();


contract BloomEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status {
        Pending,    // Newly created, waiting
        Acknowledged, // Receiver has acknowledged the deal
        Completed,  // Delivered and claimed successfully
        Disputed,   // Dispute has been raised
        Resolved,   // Dispute settled (either party can get funds)
        Reversed ,   // Funds returned to sender (timeout, cancel)
        Canceled    // Deal canceled by sender before acknowledgment
    }   

    event DealCreated(
        uint256 indexed dealId,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        address tokenAddress
    );

    struct Deal {   
        address sender;
        address receiver;
        uint256 amount;
        address tokenAddress; // Address(0) for native currency
        Status status;
        uint256 id;
    }

    mapping(uint256 => Deal) public deals;
    uint256 public dealCount;

    modifier onlySender(uint256 id) {
        if (msg.sender != deals[id].sender) {
            revert BloomEscrow__NotSender();
        }
        _;
    }
    modifier onlyReceiver(uint256 id) {
        if (msg.sender != deals[id].receiver) {
            revert BloomEscrow__NotReceiver();
        }
        _;
    }

    function createDeal(address sender, address receiver, address tokenAddress, uint256 amount) external payable nonReentrant{
        // Validate all parameters;
        if (sender == address(0) || receiver == address(0) || amount == 0) {
            revert BloomEscrow__InvalidParameters();
        }

        // Initialize a new deal
        Deal memory newDeal = Deal({
            sender: sender,
            receiver: receiver,
            amount: amount,
            tokenAddress: tokenAddress,
            status: Status.Pending,
            id: dealCount
        });

        // Store the deal
        deals[dealCount] = newDeal;
        dealCount++;

        
        // Transfer the funds from the sender to the escow;
        if (tokenAddress != address(0)){
             // Transfer for ERC20;
            IERC20 token = IERC20(tokenAddress);
            token.safeTransferFrom(sender, address(this), amount);
        } else{
            // Transfer for native;
            (bool native_success, ) = msg.sender.call{value: amount}("");
            if (!native_success) {
                revert BloomEscrow__TransferFailed();
            }
        }
       
        
        emit DealCreated(dealCount, sender, receiver, amount, tokenAddress);

    }

   

    // The purpose is just to prevent the sender from withdrawing the funds after the receiver has delivered the service
    function acknowledgeDeal(uint256 id) external onlyReceiver(id){
        Deal storage deal = deals[id];

        // Can only acknowledge deal when pending
        if (deal.status != Status. Pending){
            revert BloomEscrow__NotPending();
        }

        // Update the deal status to acknowledged
        deal.status = Status.Acknowledged;     
    }

    function unacknowledgeDeal(uint256 id) external onlyReceiver(id){
        Deal storage deal = deals[id];

        // Can only unacknowledge deal when acknowledged
        if (deal.status != Status.Acknowledged){
            revert BloomEscrow__NotAcknowledged();
        }

        // Update the deal status to pending
        deal.status = Status.Pending;     
    }

    function cancelDeal(uint256 id) external onlySender(id) {
        Deal storage deal = deals[id];
        Status status = deal.status;
        
        // You can only cancel deal if it is pending and it has not been acknowledged by the receiver
        if (status != Status.Pending){
            revert BloomEscrow__NotPending();
        }
        if (status == Status.Acknowledged){
            revert BloomEscrow__AlreadyAcknowledged();
        }
        // Update the deal status to canceled
        deal.status = Status.Canceled;

        // Transfer the funds back to the sender
        address tokenAddress = deal.tokenAddress;
        uint256 amount = deal.amount;
        address sender = deal.sender;   
        if (tokenAddress != address(0)){
             // Transfer for ERC20;
            IERC20 token = IERC20(tokenAddress);
            token.safeTransfer(sender, amount);
        } else{
            // Transfer for native;
            (bool native_success, ) = sender.call{value: amount}("");
            if (!native_success) {
                revert BloomEscrow__TransferFailed();
            }
        }

    }


     function finalizeDeal(uint256 id) external onlySender(id) {
        Deal storage deal = deals[id];

        if (msg.sender != deal.sender){
            revert BloomEscrow__NotSender();
        }

        // Can only accept deal when pending
        if (deal.status != Status. Pending){
            revert BloomEscrow__NotPending();
        }

        // Update the deal status to completed
        deal.status = Status.Completed;

        address tokenAddress = deal.tokenAddress;
        uint256 amount = deal.amount;
        address receiver = deal.receiver;   

         // Transfer the funds to the receiver
        if (tokenAddress != address(0)){
             // Transfer for ERC20;
            IERC20 token = IERC20(tokenAddress);
            token.safeTransfer(receiver, amount);
        } else{
            // Transfer for native;
            (bool native_success, ) = receiver.call{value: amount}("");
            if (!native_success) {
                revert BloomEscrow__TransferFailed();
            }
        }
    }

    function dispute(uint256 id) external {
        Deal storage deal = deals[id];

        if (msg.sender != deal.sender && msg.sender != deal.receiver){
            revert BloomEscrow__Restricted();
        }
        // Can only dispute deal when pending or acknowledged
        if (deal.status != Status. Pending && deal.status != Status.Acknowledged){
            revert BloomEscrow__CannotDispute();
        }

        // Update the deal status to disputed
        deal.status = Status.Disputed;



    }


}