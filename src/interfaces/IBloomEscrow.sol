//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {TypesLib} from "../library/TypesLib.sol";

interface IBloomEscrow {
    event DealCreated(
        uint256 indexed dealId, address indexed sender, address indexed receiver, uint256 amount, address tokenAddress
    );

    function createDeal(address receiver, uint256 amount, address tokenAddress) external payable returns (uint256);

    function acknowledgeDeal(uint256 id) external;

    function completeDeal(uint256 id) external;

    function cancelDeal(uint256 id) external;

    function reverseDeal(uint256 id) external;
    
    function updateStatus(uint256 id, TypesLib.Status newStatus) external;

    function getDeal(uint256 id) external view returns (TypesLib.Deal memory);
}
