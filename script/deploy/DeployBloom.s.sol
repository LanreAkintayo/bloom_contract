// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Bloom} from "../../src/token/Bloom.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract DeployBloom is Script {
    function run() external returns (Bloom, HelperConfig) {
        return deployBloom();
    }

    function deployBloom() internal returns (Bloom, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        address deployer;

        if (block.chainid == 31337) {
            // Local Anvil network
            deployer = msg.sender; // first default account
            vm.startBroadcast();   // uses Anvil default
        } else {
            // Any testnet/mainnet
            uint256 deployerKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerKey);
            vm.startBroadcast(deployerKey);
        }

        // Deploy the Bloom contract
        Bloom bloom = new Bloom();

        // Example: mint total supply to deployer
        // bloom.mint(deployer, bloom.totalSupply());

        vm.stopBroadcast();

        return (bloom, helperConfig);
    }
}
