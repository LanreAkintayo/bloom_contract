// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {BloomEscrow} from "../src/core/escrow/BloomEscrow.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {JurorManager} from "../src/core/disputes/JurorManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

// Import your individual deploy scripts
import {DeployBloom} from "./DeployBloom.s.sol";
import {DeployBloomEscrow} from "./DeployBloomEscrow.s.sol";
import {DeployFeeController} from "./DeployFeeController.s.sol";
import {DeployJurorManager} from "./DeployJurorManager.s.sol";

contract DeployAll is Script {
    HelperConfig.NetworkConfig networkConfig;

    function run() external {
        // 1. Deploy Bloom
        DeployBloom deployBloom = new DeployBloom();
        (Bloom bloom,) = deployBloom.run();

        // 2. Deploy FeeController
        DeployFeeController deployFeeController = new DeployFeeController();
        (FeeController feeController, HelperConfig helperConfig) = deployFeeController.run();
        networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // 3. Deploy BloomEscrow
        DeployBloomEscrow deployBloomEscrow = new DeployBloomEscrow();
        (BloomEscrow bloomEscrow,) = deployBloomEscrow.run();

        // 4. Deploy JurorManager (requires addresses of others)
        DeployJurorManager deployJurorManager = new DeployJurorManager();
        (JurorManager jurorManager,) = deployJurorManager.run(
            address(bloom),
            networkConfig.linkAddress,
            networkConfig.wrapperAddress,
            address(bloomEscrow),
            address(feeController),
            networkConfig.wrappedNativeTokenAddress
        );

        console2.log("Bloom deployed at:", address(bloom));
        console2.log("FeeController deployed at:", address(feeController));
        console2.log("BloomEscrow deployed at:", address(bloomEscrow));
        console2.log("JurorManager deployed at:", address(jurorManager));
    }
}
