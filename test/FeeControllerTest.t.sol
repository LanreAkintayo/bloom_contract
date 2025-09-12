// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {DeployFeeController} from "../script/deploy/DeployFeeController.s.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";



contract FeeControllerTest is Test {

    DeployFeeController deployFeeController;
    FeeController feeController;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    function setUp() external {
        deployFeeController = new DeployFeeController();
        (feeController, helperConfig) = deployFeeController.run();
        networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // Add price feed to fee controller;
        vm.startPrank(feeController.owner());
        feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);
        vm.stopPrank();

    }


    function testCalculateEscrowFee() external view {
        uint256 amount = 100e18;
        uint256 escrowFee = feeController.calculateEscrowFee(amount);

        assertEq(escrowFee, 1e18);

    }

    function testCalculateAppealFee() external view {
        uint256 round = 1;
        uint256 minimumAppealFee = feeController.minimumAppealFee();         // 10e18 = 10 in USDC scaled to e18
        uint256 disputeFeePercentage = feeController.disputeFeePercentage(); // 500 = 5%
        uint256 maximumPercentage = feeController.MAX_FEE_PERCENTAGE();
        
        // If I charge in USDC, the appeal fee should be calculated accurately in USDC
        address usdcTokenAddress = networkConfig.usdcTokenAddress;
        uint256 amountInUsdc = 100e8;
        uint256 actualAppealFee = feeController.calculateAppealFee(usdcTokenAddress, amountInUsdc, round);
        assertEq(10e8, actualAppealFee); 

        // If I charge in DAI, the appeal fee should be calculated accurately in DAI
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 amountInDai = 100e18;
        uint256 actualAppealFeeInDai = feeController.calculateAppealFee(daiTokenAddress, amountInDai, round);
        assertEq(10e18, actualAppealFeeInDai); 
        
        
        // If I charge in ETH, the appeal fee should be calculated accurately in ETH
         address wethTokenAddress = networkConfig.wethTokenAddress;
        uint256 amountInWeth = 1000e18;
        uint256 actualAppealFeeInWeth = feeController.calculateAppealFee(wethTokenAddress, amountInWeth, round);
        uint256 expectedAppealFeeInWeth = amountInWeth * disputeFeePercentage * 2 ** (round - 1) / maximumPercentage;
        assertEq(expectedAppealFeeInWeth, 50e18);
        assertEq(expectedAppealFeeInWeth, actualAppealFeeInWeth); 
    }
}

