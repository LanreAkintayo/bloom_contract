//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {JurorManager} from "../../src/core/disputes/JurorManager.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {DeployedAddresses} from "./DeployedAddresses.sol";
import {DisputeStorage} from "../../src/core/disputes/DisputeStorage.sol";

contract DeployDisputeStorage is Script {
    function run() external returns (DisputeStorage, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // Pick addresses automatically if zero
        address bloomTokenAddress = DeployedAddresses.getLastBloom(block.chainid);
        address escrowAddress = DeployedAddresses.getLastBloomEscrow(block.chainid);
        address feeControllerAddress = DeployedAddresses.getLastFeeController(block.chainid);
        address wrappedNativeTokenAddress = networkConfig.wrappedNativeTokenAddress;

        return deploy(            
            escrowAddress,
            feeControllerAddress,
            bloomTokenAddress,
            wrappedNativeTokenAddress,
            helperConfig
        );
    }

    function deploy(
        address escrowAddress,
        address feeControllerAddress,
        address bloomTokenAddress,
        address wrappedNativeTokenAddress,
        HelperConfig helperConfig
    ) public returns (DisputeStorage, HelperConfig) {
        uint256 deployerKey;
        if (block.chainid == 31337) {
            vm.startBroadcast(); // Anvil default
        } else {
            deployerKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerKey);
        }

        DisputeStorage disputeStorage = new DisputeStorage(
            escrowAddress,
            feeControllerAddress,
            bloomTokenAddress,
            wrappedNativeTokenAddress
        );

        vm.stopBroadcast();
        return (disputeStorage, helperConfig);
    }
}
