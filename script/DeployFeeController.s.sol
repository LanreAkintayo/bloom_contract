//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployFeeController is Script {
    FeeController public feeController;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getActiveNetworkConfig();

        // Deploy the contracts;
        vm.startBroadcast();
        deployContract();
    }

    function deployContract() internal returns (FeeController) {
        // Implementation will sit here
    }
}
