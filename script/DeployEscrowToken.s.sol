//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import {Script} from "forge-std/Script.sol";
import {EscrowTokens} from "../src/core/escrow/EscrowTokens.sol";
import {Bloom} from "../src/token/Bloom.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployEscrowTokens is Script {
    EscrowTokens public escrowTokens;

    function run() external {
        deployContract();
    }


    function deployContract() internal returns (EscrowTokens){
        // Implementation will sit here
    }

}