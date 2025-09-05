//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import {Script} from "forge-std/Script.sol";
import {BloomEscrow} from "../src/core/escrow/BloomEscrow.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployBloomEscrow is Script {
    BloomEscrow public bloomEscrow;

    function run() external {
        deployContract();
    }


    function deployContract() internal returns (BloomEscrow){
        // Implementation will sit here
    }

}