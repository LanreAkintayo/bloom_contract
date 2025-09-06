// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TypesLib} from "../../library/TypesLib.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";
import {EscrowTokens} from "./EscrowTokens.sol";
import {console, Test} from "forge-std/Test.sol";

contract BloomEscrow is ReentrancyGuard, EscrowTokens {
    using SafeERC20 for IERC20;

    //////////////////////////
    // ERRORS
    //////////////////////////

    error BloomEscrow__InvalidParameters();
    error BloomEscrow__TransferFailed();
    error BloomEscrow__NotSender();
    error BloomEscrow__NotPending();
    error BloomEscrow__NotReceiver();
    error BloomEscrow__NotAcknowledged();
    error BloomEscrow__AlreadyAcknowledged();
    error BloomEscrow__Restricted();
    error BloomEscrow__CannotDispute();
    error BloomEscrow__ZeroAddress();
    error BloomEscrow__AlreadyFinalized();
    error BloomEscrow__CannotFinalize();

    //////////////////////////
    // EVENTS
    //////////////////////////

    event DealCreated(
        uint256 indexed dealId, address indexed sender, address indexed receiver, uint256 amount, address tokenAddress
    );
    event FundsReleased(address winner, uint256 id);

    //////////////////////////
    // STATE VARIABLES
    //////////////////////////

    mapping(uint256 => TypesLib.Deal) public deals;
    uint256 public dealCount;
    address public disputeManagerAddress;
    address public feeControllerAddress;

    //////////////////////////
    // MODIFIERS
    //////////////////////////

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

    //////////////////////////
    // EXTERNAL FUNCTIONS
    //////////////////////////

    function addDisputeManager(address _disputeManagerAddress) external onlyOwner {
        if (_disputeManagerAddress == address(0)) {
            revert BloomEscrow__ZeroAddress();
        }
        // Only the contract deployer can set the dispute manager address
        disputeManagerAddress = _disputeManagerAddress;
    }

    function addFeeController(address _feeControllerAddress) external onlyOwner {
        // Only the contract deployer can set the fee controller address
        if (_feeControllerAddress == address(0)) {
            revert BloomEscrow__ZeroAddress();
        }

        feeControllerAddress = _feeControllerAddress;
    }

    function createDeal(address sender, address receiver, address tokenAddress, uint256 amount)
        external
        payable
        nonReentrant
    {
        // Validate parameters
        if (sender == address(0) || receiver == address(0) || amount == 0) {
            revert BloomEscrow__InvalidParameters();
        }

        if (tokenAddress != address(0) && msg.value > 0 && !isSupported[tokenAddress]) {
            revert EscrowTokens__NotSupported();
        }

        // Initialize a new deal
        TypesLib.Deal memory newDeal = TypesLib.Deal({
            sender: sender,
            receiver: receiver,
            amount: amount,
            tokenAddress: tokenAddress,
            status: TypesLib.Status.Pending,
            id: dealCount
        });

        // Store the deal
        deals[dealCount] = newDeal;
        dealCount++;

        uint256 totalAmount = amount;

        // Charge escrow fee (if any) - omitted for simplicity
        IFeeController feeController = IFeeController(feeControllerAddress);

        if (feeController.escrowFeePercentage() > 0) {
            uint256 escrowFee = feeController.calculateEscrowFee(amount);
            totalAmount += escrowFee;
        }

        console.log("msg.value: ", msg.value);
        console.log("total amount: ", totalAmount);
        if (msg.value > 0 && msg.value < totalAmount) {
            revert BloomEscrow__TransferFailed();
        }

        // Transfer the funds to escrow
        if (tokenAddress != address(0)) {
            IERC20 token = IERC20(tokenAddress);
            token.safeTransferFrom(sender, address(this), totalAmount);
        }

        emit DealCreated(dealCount, sender, receiver, totalAmount, tokenAddress);
    }

    function acknowledgeDeal(uint256 id) external onlyReceiver(id) {
        TypesLib.Deal storage deal = deals[id];

        if (deal.status != TypesLib.Status.Pending) {
            revert BloomEscrow__NotPending();
        }

        deal.status = TypesLib.Status.Acknowledged;
    }

    function unacknowledgeDeal(uint256 id) external onlyReceiver(id) {
        TypesLib.Deal storage deal = deals[id];

        if (deal.status != TypesLib.Status.Acknowledged) {
            revert BloomEscrow__NotAcknowledged();
        }

        deal.status = TypesLib.Status.Pending;
    }

    function cancelDeal(uint256 id) external onlySender(id) {
        TypesLib.Deal storage deal = deals[id];
        TypesLib.Status status = deal.status;

        if (status != TypesLib.Status.Pending) {
            revert BloomEscrow__NotPending();
        }
        if (status == TypesLib.Status.Acknowledged) {
            revert BloomEscrow__AlreadyAcknowledged();
        }

        deal.status = TypesLib.Status.Canceled;

        address tokenAddress = deal.tokenAddress;
        uint256 amount = deal.amount;
        address sender = deal.sender;

        if (tokenAddress != address(0)) {
            IERC20 token = IERC20(tokenAddress);
            token.safeTransfer(sender, amount);
        } else {
            (bool native_success,) = sender.call{value: amount}("");
            if (!native_success) {
                revert BloomEscrow__TransferFailed();
            }
        }
    }

    function finalizeDeal(uint256 id) external onlySender(id) {
        TypesLib.Deal storage deal = deals[id];

        if (deal.status == TypesLib.Status.Completed) {
            revert BloomEscrow__AlreadyFinalized();
        }

        if (deal.status != TypesLib.Status.Acknowledged && deal.status != TypesLib.Status.Pending) {
            revert BloomEscrow__CannotFinalize();
        }

        deal.status = TypesLib.Status.Completed;

        address tokenAddress = deal.tokenAddress;
        uint256 amount = deal.amount;
        address receiver = deal.receiver;

        if (tokenAddress != address(0)) {
            IERC20 token = IERC20(tokenAddress);
            token.safeTransfer(receiver, amount);
        } else {
            (bool native_success,) = receiver.call{value: amount}("");
            if (!native_success) {
                revert BloomEscrow__TransferFailed();
            }
        }
    }

    function releaseFunds(address winner, uint256 id) external {
        if (msg.sender != disputeManagerAddress) {
            revert BloomEscrow__Restricted();
        }

        // Change the deal status to resolved;
        TypesLib.Deal storage deal = deals[id];
        deal.status = TypesLib.Status.Resolved;

        // Send funds to the winner;
        address tokenAddress = deal.tokenAddress;
        uint256 amount = deal.amount;
        if (tokenAddress != address(0)) {
            IERC20 token = IERC20(tokenAddress);
            token.safeTransfer(winner, amount);
        } else {
            (bool native_success,) = winner.call{value: amount}("");
            if (!native_success) {
                revert BloomEscrow__TransferFailed();
            }
        }

        // Emit event;
        emit FundsReleased(winner, id);
    }

    function updateStatus(uint256 id, TypesLib.Status newStatus) external {
        if (msg.sender != disputeManagerAddress) {
            revert BloomEscrow__Restricted();
        }

        TypesLib.Deal storage deal = deals[id];
        deal.status = newStatus;
    }

    function getDeal(uint256 id) external view returns (TypesLib.Deal memory) {
        return deals[id];
    }
}
