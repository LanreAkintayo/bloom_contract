//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Script} from "forge-std/Script.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBloom is Script {
    function run() external returns (Bloom, HelperConfig) {
        return deployBloom();
    }

    function deployBloom() internal returns (Bloom, HelperConfig) {
        // Implementation will sit here
        HelperConfig helperConfig = new HelperConfig();

        // Deploy the contracts;
        vm.startBroadcast();
        Bloom bloom = new Bloom();
        vm.stopBroadcast();

        return (bloom, helperConfig);
    }
}
