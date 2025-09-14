//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DisputeManager} from "../../src/core/disputes/DisputeManager.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {DeployedAddresses} from "./DeployedAddresses.sol";

contract DeployDisputeManager is Script {
    function run() external returns (DisputeManager, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);
        address storageAddress = DeployedAddresses.getLastDisputeStorage(block.chainid);

        return deploy(
            storageAddress,
            helperConfig
        );
    }

    function deploy(
        address storageAddress,
        HelperConfig helperConfig
    ) public returns (DisputeManager, HelperConfig) {
        uint256 deployerKey;
        if (block.chainid == 31337) {
            vm.startBroadcast(); // Anvil default
        } else {
            deployerKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerKey);
        }

        DisputeManager disputeManager = new DisputeManager(
        storageAddress
            // escrowAddress,
            // feeControllerAddress,
            // wrappedNativeTokenAddress
        );

        vm.stopBroadcast();
        return (disputeManager, helperConfig);
    }
}
