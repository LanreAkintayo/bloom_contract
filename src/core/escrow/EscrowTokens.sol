// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract EscrowTokens is Ownable{
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error EscrowTokens__ZeroAddress();
    error EscrowTokens__NotSupported();
    error EscrowTokens__AlreadySupported();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => bool) public isSupported;
    mapping(address => uint256) public tokenIndex; 
    address[] public allSupportedTokens;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event TokenAdded(address indexed tokenAddress);
    event TokenRemoved(address indexed tokenAddress);

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function addToken(address tokenAddress) external onlyOwner {
        if (tokenAddress == address(0)) {
            revert EscrowTokens__ZeroAddress();
        }
        if (isSupported[tokenAddress]) {
            revert EscrowTokens__AlreadySupported();
        }

        isSupported[tokenAddress] = true;
        tokenIndex[tokenAddress] = allSupportedTokens.length;
        allSupportedTokens.push(tokenAddress);

        emit TokenAdded(tokenAddress);
    }

    function removeToken(address tokenAddress) external onlyOwner {
        if (tokenAddress == address(0)) {
            revert EscrowTokens__ZeroAddress();
        }
        if (!isSupported[tokenAddress]) {
            revert EscrowTokens__NotSupported();
        }

        uint256 index = tokenIndex[tokenAddress];
        uint256 lastIndex = allSupportedTokens.length - 1;

        if (index != lastIndex) {
            address lastToken = allSupportedTokens[lastIndex];
            allSupportedTokens[index] = lastToken;
            tokenIndex[lastToken] = index;
        }

        isSupported[tokenAddress] = false;
        allSupportedTokens.pop();
        delete tokenIndex[tokenAddress];

        emit TokenRemoved(tokenAddress);
    }
}
