//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";

contract JurorManager {
    struct Juror {
        address jurorAddress;
        uint256 stakeAmount;
        uint256[] assignedDisputes;
        bool isActive;
    }

    function registerJuror() external {
        
    }
}
