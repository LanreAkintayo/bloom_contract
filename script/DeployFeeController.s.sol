//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployFeeController is Script {

    uint256 public escrowFeePercentage = 100;  // 1% fee
    uint256 public disputeFeePercentage =500;  // 5%
    uint256 public minimumAppealFee = 10e18; // in USD scaled to 10^18
    // uint256 public jurorShare;

    function run() external returns (FeeController, HelperConfig) {
        return deployFeeController();
    }

    function deployFeeController() internal returns (FeeController, HelperConfig) {
        // Implementation will sit here
        HelperConfig helperConfig = new HelperConfig();
        // HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // Deploy the contracts;
        vm.startBroadcast();
        FeeController feeController =
            new FeeController(escrowFeePercentage, disputeFeePercentage, minimumAppealFee);
        vm.stopBroadcast();

        return (feeController, helperConfig);
    }
}
