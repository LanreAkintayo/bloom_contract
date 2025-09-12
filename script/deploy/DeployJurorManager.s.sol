//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {JurorManager} from "../../src/core/disputes/JurorManager.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {DeployedAddresses} from "./DeployedAddresses.sol";

contract DeployJurorManager is Script {
    function run() external returns (JurorManager, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // Pick addresses automatically if zero
        address bloomTokenAddress = DeployedAddresses.getLastBloom(block.chainid);
        address linkAddress = networkConfig.linkAddress;
        address wrapperAddress = networkConfig.wrapperAddress;
        address escrowAddress = DeployedAddresses.getLastBloomEscrow(block.chainid);
        address feeControllerAddress = DeployedAddresses.getLastFeeController(block.chainid);
        address wrappedNativeTokenAddress = networkConfig.wrappedNativeTokenAddress;

        return deploy(
            bloomTokenAddress,
            linkAddress,
            wrapperAddress,
            escrowAddress,
            feeControllerAddress,
            wrappedNativeTokenAddress,
            helperConfig
        );
    }

    function deploy(
        address bloomTokenAddress,
        address linkAddress,
        address wrapperAddress,
        address escrowAddress,
        address feeControllerAddress,
        address wrappedNativeTokenAddress,
        HelperConfig helperConfig
    ) public returns (JurorManager, HelperConfig) {
        uint256 deployerKey;
        if (block.chainid == 31337) {
            vm.startBroadcast(); // Anvil default
        } else {
            deployerKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerKey);
        }

        JurorManager jurorManager = new JurorManager(
            bloomTokenAddress,
            linkAddress,
            wrapperAddress,
            escrowAddress,
            feeControllerAddress,
            wrappedNativeTokenAddress
        );

        vm.stopBroadcast();
        return (jurorManager, helperConfig);
    }
}
