//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import {Script} from "forge-std/Script.sol";
import {Bloom} from "../src/token/Bloom.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployBloom is Script {
    Bloom public bloom;

    function run() external {
        deployContract();
    }


    function deployContract() internal returns (Bloom){
        // Implementation will sit here
    }

}