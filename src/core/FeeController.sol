// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title FeeController
/// @notice Centralized fee management for Bloom (escrow, dispute, and juror shares)
contract FeeController is Ownable {

    /*//////////////////////////////////////////////////////////////
                              STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    uint256 public escrowFee;
    uint256 public disputeFee;
    uint256 public jurorShare;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_FEE = 10_000; // Represents 100.00%

    /*//////////////////////////////////////////////////////////////
                                  ERRORS
    //////////////////////////////////////////////////////////////*/

    error FeeController__InvalidFee();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 _escrowFee,
        uint256 _disputeFee,
        uint256 _jurorShare
    ) Ownable(msg.sender) {
        escrowFee = _escrowFee;
        disputeFee = _disputeFee;
        jurorShare = _jurorShare;
    }

    /*//////////////////////////////////////////////////////////////
                                SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setEscrowFee(uint256 _escrowFee) external onlyOwner {
        if (_escrowFee > MAX_FEE) {
            revert FeeController__InvalidFee();
        }
        escrowFee = _escrowFee;
    }

    function setDisputeFee(uint256 _disputeFee) external onlyOwner {
        if (_disputeFee > MAX_FEE) {
            revert FeeController__InvalidFee();
        }
        disputeFee = _disputeFee;
    }

    function setJurorShare(uint256 _jurorShare) external onlyOwner {
        if (_jurorShare > MAX_FEE) {
            revert FeeController__InvalidFee();
        }
        jurorShare = _jurorShare;
    }

    /*//////////////////////////////////////////////////////////////
                              CALCULATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateEscrowFee(uint256 amount) external view returns (uint256) {
        return (amount * escrowFee) / MAX_FEE;
    }

    function calculateDisputeFee(uint256 amount) external view returns (uint256) {
        return (amount * disputeFee) / MAX_FEE;
    }

    function calculateJurorShare(uint256 amount) external view returns (uint256) {
        return (amount * jurorShare) / MAX_FEE;
    }
}
