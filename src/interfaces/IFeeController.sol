//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeeController {
    function escrowFeePercentage() external view returns (uint256);
    function disputeFeePercentage() external view returns (uint256);
    function jurorShare() external view returns (uint256);
    function setEscrowFeePercentage(uint256 _escrowFee) external;
    function setDisputeFeePercentage(uint256 _disputeFee) external;
    function setJurorShare(uint256 _jurorShare) external;
    function calculateEscrowFee(uint256 amount) external view returns (uint256);
    function calculateDisputeFee(uint256 amount) external view returns (uint256);
    function calculateJurorShare(uint256 amount) external view returns (uint256);
    function calculateAppealFee(address tokenAddress, uint256 amount, uint256 round) external view returns(uint256);
}