// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title FeePercentageController
/// @notice Centralized fee management for Bloom (escrow, dispute, and juror shares)
contract FeeController is Ownable {
    /*//////////////////////////////////////////////////////////////
                              STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public escrowFeePercentage;
    uint256 public disputeFeePercentage;
    uint256 public jurorShare;
    uint256 public minimumAppealFee; // in USD scaled to 10^18

    mapping(address => address) public dataFeedAddresses;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_FEE_PERCENTAGE = 10_000; // Represents 100.00%

    /*//////////////////////////////////////////////////////////////
                                  ERRORS
    //////////////////////////////////////////////////////////////*/

    error FeePercentageController__InvalidFeePercentage();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 _escrowFeePercentage,
        uint256 _disputeFeePercentage,
        uint256 _minimumAppealFeePercentage,
        uint256 _jurorShare
    ) Ownable(msg.sender) {
        escrowFeePercentage = _escrowFeePercentage;
        disputeFeePercentage = _disputeFeePercentage;
        minimumAppealFee = _minimumAppealFeePercentage;
        jurorShare = _jurorShare;
    }

    /*//////////////////////////////////////////////////////////////
                                SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setEscrowFeePercentage(uint256 _escrowFeePercentage) external onlyOwner {
        if (_escrowFeePercentage > MAX_FEE_PERCENTAGE) {
            revert FeePercentageController__InvalidFeePercentage();
        }
        escrowFeePercentage = _escrowFeePercentage;
    }

    function setDisputeFeePercentage(uint256 _disputeFeePercentage) external onlyOwner {
        if (_disputeFeePercentage > MAX_FEE_PERCENTAGE) {
            revert FeePercentageController__InvalidFeePercentage();
        }
        disputeFeePercentage = _disputeFeePercentage;
    }

    function setJurorShare(uint256 _jurorShare) external onlyOwner {
        if (_jurorShare > MAX_FEE_PERCENTAGE) {
            revert FeePercentageController__InvalidFeePercentage();
        }
        jurorShare = _jurorShare;
    }

    /*//////////////////////////////////////////////////////////////
                              CALCULATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateEscrowFee(uint256 amount) external view returns (uint256) {
        return (amount * escrowFeePercentage) / MAX_FEE_PERCENTAGE;
    }

    function calculateDisputeFee(uint256 amount) external view returns (uint256) {
        return (amount * disputeFeePercentage) / MAX_FEE_PERCENTAGE;
    }

    function calculateJurorShare(uint256 amount) external view returns (uint256) {
        return (amount * jurorShare) / MAX_FEE_PERCENTAGE;
    }

    function calculateAppealFee(address tokenAddress, uint256 amount, uint256 round) external view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(dataFeedAddresses[tokenAddress]);

        uint8 tokenDecimals = dataFeed.decimals();

        (, int256 answer,,,) = dataFeed.latestRoundData();

        uint256 priceInWei = uint256(answer) * 10 ** (18 - tokenDecimals);
        uint256 minimumAppealFeeInTokenScale = (minimumAppealFee * tokenDecimals) / priceInWei;

        uint256 potentialAppealFee = (amount * disputeFeePercentage * 2 ** (round - 1)) / MAX_FEE_PERCENTAGE;

        uint256 appealFee =
            potentialAppealFee > minimumAppealFeeInTokenScale ? potentialAppealFee : minimumAppealFeeInTokenScale;
        return appealFee;
    }

    function addToDataFeed(address tokenAddress, address dataFeed) external onlyOwner {
        dataFeedAddresses[tokenAddress] = dataFeed;
    }
}
