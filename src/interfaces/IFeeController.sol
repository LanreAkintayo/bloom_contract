//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFeeController {
    function escrowFee() external view returns (uint256);
    function disputeFee() external view returns (uint256);
    function jurorShare() external view returns (uint256);
    function setEscrowFee(uint256 _escrowFee) external;
    function setDisputeFee(uint256 _disputeFee) external;
    function setJurorShare(uint256 _jurorShare) external;
    function calculateEscrowFee(uint256 amount) external view returns (uint256);
    function calculateDisputeFee(uint256 amount) external view returns (uint256);
    function calculateJurorShare(uint256 amount) external view returns (uint256);
}