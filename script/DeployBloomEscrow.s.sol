//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BloomEscrow} from "../src/core/escrow/BloomEscrow.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {console} from "forge-std/console.sol";

contract DeployBloomEscrow is Script {
    function run() external returns (BloomEscrow, HelperConfig) {
        return deployBloomEscrow();
    }

    function deployBloomEscrow() internal returns (BloomEscrow, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);
        address wrappedNativeTokenAddress = networkConfig.wrappedNativeTokenAddress;

        console.log("Wrappd Native token address: ", wrappedNativeTokenAddress);

        // Deploy the contracts;
        vm.startBroadcast();
        BloomEscrow bloomEscrow = new BloomEscrow(wrappedNativeTokenAddress);
        vm.stopBroadcast();

        return (bloomEscrow, helperConfig);
    }
}
