//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {JurorManager} from "../src/core/disputes/JurorManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployJurorManager is Script {
    function run(
        address _bloomTokenAddress,
        address _linkAddress,
        address _wrapperAddress,
        address _escrowAddress,
        address _feeControllerAddress
    ) external returns (JurorManager, HelperConfig) {
        return
            deployJurorManager(_bloomTokenAddress, _linkAddress, _wrapperAddress, _escrowAddress, _feeControllerAddress);
    }

    function deployJurorManager(
        address bloomTokenAddress,
        address linkAddress,
        address wrapperAddress,
        address escrowAddress,
        address feeControllerAddress
    ) internal returns (JurorManager, HelperConfig) {
        // Implementation will sit here
        HelperConfig helperConfig = new HelperConfig();
        
        // Deploy the contracts;
        vm.startBroadcast();
        JurorManager jurorManager = new JurorManager(bloomTokenAddress, linkAddress, wrapperAddress, escrowAddress, feeControllerAddress);
        vm.stopBroadcast();

        return (jurorManager, helperConfig);
    }
}
