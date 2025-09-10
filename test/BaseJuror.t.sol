// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";

// Scripts
import {DeployBloom} from "../script/DeployBloom.s.sol";
import {DeployBloomEscrow} from "../script/DeployBloomEscrow.s.sol";
import {DeployFeeController} from "../script/DeployFeeController.s.sol";
import {DeployJurorManager} from "../script/DeployJurorManager.s.sol";

// Core contracts
import {Bloom} from "../src/token/Bloom.sol";
import {BloomEscrow} from "../src/core/escrow/BloomEscrow.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {JurorManager} from "../src/core/disputes/JurorManager.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract BaseJuror is Test {
    // Deploy scripts
    DeployBloom deployBloom;
    DeployBloomEscrow deployBloomEscrow;
    DeployFeeController deployFeeController;
    DeployJurorManager deployJurorManager;

    // Core contracts
    Bloom bloom;
    BloomEscrow bloomEscrow;
    FeeController feeController;
    JurorManager jurorManager;

    // Config
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    // Test actors
    address sender;
    address receiver;

    function setUp() public virtual {
        // Deploy Bloom
        deployBloom = new DeployBloom();
        (bloom, helperConfig) = deployBloom.run();
        networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // Deploy FeeController
        deployFeeController = new DeployFeeController();
        (feeController, ) = deployFeeController.run();

        // Deploy BloomEscrow
        deployBloomEscrow = new DeployBloomEscrow();
        (bloomEscrow, ) = deployBloomEscrow.run();

        // Deploy JurorManager
        deployJurorManager = new DeployJurorManager();
        (jurorManager, ) = deployJurorManager.run(
            address(bloom),
            networkConfig.linkAddress,
            networkConfig.wrapperAddress,
            address(bloomEscrow),
            address(feeController),
            networkConfig.wrappedNativeTokenAddress
        );

        // Link FeeController and dispute manager to BloomEscrow
        vm.startPrank(bloomEscrow.owner());

        // console .log("Fee controller address: ", address(feeController));
        // console.log("Juror manager address: ", address(jurorManager));
        // console.log("usdcTokenAddress: ", networkConfig.usdcTokenAddress);
        // console.log("daiTokenAddress: ", networkConfig.daiTokenAddress);
        // console.log("wethTokenAddress: ", networkConfig.wethTokenAddress);


        bloomEscrow.addFeeController(address(feeController));
        bloomEscrow.addDisputeManager(address(jurorManager));

        bloomEscrow.addToken(networkConfig.usdcTokenAddress);
        bloomEscrow.addToken(networkConfig.daiTokenAddress);
        bloomEscrow.addToken(networkConfig.wethTokenAddress);
        
        vm.stopPrank();

        // Configure FeeController
        vm.startPrank(feeController.owner());
        feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);
        vm.stopPrank();

        

        // 8. Test actors
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
    }
}
