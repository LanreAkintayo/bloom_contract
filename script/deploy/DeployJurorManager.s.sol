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
        address storageAddress = DeployedAddresses.getLastDisputeStorage(block.chainid);
        // address bloomTokenAddress = DeployedAddresses.getLastBloom(block.chainid);
        address linkAddress = networkConfig.linkAddress;
        address wrapperAddress = networkConfig.wrapperAddress;
        
        return deploy(
            storageAddress,
            // bloomTokenAddress,
            linkAddress,
            wrapperAddress,
            helperConfig
        );
    }

    function deploy(
        address storageAddress,
        // address bloomTokenAddress,
        address linkAddress,
        address wrapperAddress,
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
            storageAddress,
            // bloomTokenAddress,
            linkAddress,
            wrapperAddress
            // escrowAddress,
            // feeControllerAddress,
            // wrappedNativeTokenAddress
        );

        vm.stopBroadcast();
        return (jurorManager, helperConfig);
    }
}
