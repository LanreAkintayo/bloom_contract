//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FeeController} from "../../src/core/FeeController.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {console} from "forge-std/console.sol";
import {DeployedAddresses} from "../../script/deploy/DeployedAddresses.sol";

contract SetupFeeController is Script {
    function run() external  {
         HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);
        address feeControllerAddress = DeployedAddresses.getLastFeeController(block.chainid);

        FeeController feeController = FeeController(feeControllerAddress);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);

        vm.stopBroadcast();       
    }
}
