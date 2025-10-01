// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Bloom} from "../../src/token/Bloom.sol";
import {BloomEscrow} from "../../src/core/escrow/BloomEscrow.sol";
import {FeeController} from "../../src/core/FeeController.sol";
import {JurorManager} from "../../src/core/disputes/JurorManager.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {DisputeStorage} from "../../src/core/disputes/DisputeStorage.sol";
import {DisputeManager} from "../../src/core/disputes/DisputeManager.sol";

// Import your individual deploy scripts
import {DeployBloom} from "./DeployBloom.s.sol";
import {DeployBloomEscrow} from "./DeployBloomEscrow.s.sol";
import {DeployFeeController} from "./DeployFeeController.s.sol";
import {DeployJurorManager} from "./DeployJurorManager.s.sol";
import {DeployDisputeStorage} from "./DeployDisputeStorage.s.sol";
import {DeployDisputeManager} from "./DeployDisputeManager.s.sol";

contract DeployAll is Script {
    HelperConfig.NetworkConfig networkConfig;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        
        // 2. Deploy FeeController
        DeployFeeController deployFeeController = new DeployFeeController();
        (FeeController feeController, HelperConfig helperConfig) = deployFeeController.run();
        networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // 3. Deploy BloomEscrow
        DeployBloomEscrow deployBloomEscrow = new DeployBloomEscrow();
        (BloomEscrow bloomEscrow,) = deployBloomEscrow.run();

        // Deploy Dispute Stoarge
        DeployDisputeStorage deployDisputeStorage = new DeployDisputeStorage();
        (DisputeStorage disputeStorage,) = deployDisputeStorage.deploy(
            address(bloomEscrow),
            address(feeController),
            networkConfig.bloomTokenAddress,
            networkConfig.wrappedNativeTokenAddress,
            helperConfig
        );

        // Deploy DisputeManager
        DeployDisputeManager deployDisputeManager = new DeployDisputeManager();
        (DisputeManager disputeManager,) = deployDisputeManager.deploy(address(disputeStorage), helperConfig);

        // 4. Deploy JurorManager (requires addresses of others)
        DeployJurorManager deployJurorManager = new DeployJurorManager();
        (JurorManager jurorManager,) = deployJurorManager.deploy(
            address(disputeStorage), networkConfig.linkAddress, networkConfig.wrapperAddress, helperConfig
        );

        console2.log("Bloom deployed at:", networkConfig.bloomTokenAddress);
        console2.log("FeeController deployed at:", address(feeController));
        console2.log("BloomEscrow deployed at:", address(bloomEscrow));
        console2.log("JurorManager deployed at:", address(jurorManager));
        console2.log("DisputeManager deployed at:", address(disputeManager));
        console2.log("DisputeStorage deployed at:", address(disputeStorage));

        // Set up Bloom Escrow;
        vm.startBroadcast(deployerKey);
        bloomEscrow.addFeeController(address(feeController));
        bloomEscrow.addDisputeManager(address(disputeManager));

        bloomEscrow.addToken(networkConfig.usdcTokenAddress);
        bloomEscrow.addToken(networkConfig.daiTokenAddress);
        bloomEscrow.addToken(networkConfig.wethTokenAddress);

        // Set up FeeController
        feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);

        // Set up DisputeManager;
        disputeManager.addJurorManager(address(jurorManager));

        vm.stopBroadcast();
    }
}
