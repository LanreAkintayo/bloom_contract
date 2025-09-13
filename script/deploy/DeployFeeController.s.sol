//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FeeController} from "../../src/core/FeeController.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract DeployFeeController is Script {
    uint256 public escrowFeePercentage = 100; // 1% fee
    uint256 public disputeFeePercentage = 500; // 5%
    uint256 public minimumAppealFee = 10e18; // in USD scaled to 10^18

    function run() external returns (FeeController, HelperConfig) {
        return deployFeeController();
    }

    function deployFeeController() internal returns (FeeController, HelperConfig) {
        // Implementation will sit here
        HelperConfig helperConfig = new HelperConfig();

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);

        address deployer;
        FeeController feeController;

        if (block.chainid == 31337) {
            // Local Anvil network
            deployer = msg.sender; // first default account
            vm.startBroadcast(); // uses Anvil default

            feeController = new FeeController(escrowFeePercentage, disputeFeePercentage, minimumAppealFee);
        } else {
            // Any testnet/mainnet
            uint256 deployerKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerKey);
            vm.startBroadcast(deployerKey);

            feeController = new FeeController(escrowFeePercentage, disputeFeePercentage, minimumAppealFee);

            feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
            feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
            feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);
        }

        vm.stopBroadcast();

        return (feeController, helperConfig);
    }
}
