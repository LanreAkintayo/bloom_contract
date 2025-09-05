// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployBloomEscrow} from "../script/DeployBloomEscrow.s.sol";
import {BloomEscrow} from "../src/core/escrow/BloomEscrow.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {DeployFeeController} from "../script/DeployFeeController.s.sol";
import {TypesLib} from "../src/library/TypesLib.sol";


contract BloomEscrowTest is Test {
    DeployBloomEscrow deployBloomEscrow;
    DeployFeeController deployFeeController;
    BloomEscrow bloomEscrow;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;
    FeeController feeController;

    function setUp() external {
        deployBloomEscrow = new DeployBloomEscrow();
        (bloomEscrow, helperConfig) = deployBloomEscrow.run();
        networkConfig = helperConfig.getConfigByChainId(block.chainid);

        setUpFeeController();

        vm.startPrank(bloomEscrow.owner());
        // Add fee controller to the bloom escrow
        bloomEscrow.addFeeController(address(feeController));

        // Add supported tokens to the bloom escrow
        bloomEscrow.addToken(networkConfig.usdcTokenAddress);
        bloomEscrow.addToken(networkConfig.daiTokenAddress);
        bloomEscrow.addToken(networkConfig.wethTokenAddress);
        vm.stopPrank();
    }

    function setUpFeeController() internal {
        deployFeeController = new DeployFeeController();
        (feeController, helperConfig ) = deployFeeController.run();
        networkConfig = helperConfig.getConfigByChainId(block.chainid);

        // Add price feed to fee controller;
        vm.startPrank(feeController.owner());
        feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
        feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);
        vm.stopPrank();
    }

    function testCreateDealWithERC20() external {
        // Create a deal and check if all states have been updated;
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address tokenAddress = networkConfig.usdcTokenAddress;
        uint256 amount = 100e8;
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        // Mint some usdc to sender;
        IERC20Mock token = IERC20Mock(tokenAddress);
        vm.prank(address(helperConfig));
        token.mint(sender, 1_000_000e18);

        vm.startPrank(sender);
        // Approve bloom escrow to spend your token
        token.approve(address(bloomEscrow), totalAmount);
        bloomEscrow.createDeal(sender, receiver, tokenAddress, amount);
        vm.stopPrank();

        // Check states;
        assertEq(bloomEscrow.dealCount(), 1);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(0);
        assertEq(deal.sender, sender);
        assertEq(deal.receiver, receiver);
        assertEq(deal.tokenAddress, tokenAddress);
        assertEq(deal.amount, amount);
        assertEq(uint8(deal.status), uint8(TypesLib.Status.Pending));
        assertEq(deal.id, 0);

        // Check escrow balance;
        assertEq(token.balanceOf(address(bloomEscrow)), totalAmount);
    }

    function testCreateDealWithETH() external {
       // Create a deal and check if all states have been updated;
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address tokenAddress = address(0);
        uint256 amount = 10e8;
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;
        console.log("Outide, the totalAmount: %s", totalAmount);

        // Fund the sender with eth;
        deal(sender, 100 ether); // now deployer has 100 ETH
        assertEq(sender.balance, 100 ether);

       
        vm.startPrank(sender);
        bloomEscrow.createDeal{value: totalAmount}(sender, receiver, tokenAddress, amount);
        vm.stopPrank();

        // Check states;
        assertEq(bloomEscrow.dealCount(), 1);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(0);
        assertEq(deal.sender, sender);
        assertEq(deal.receiver, receiver);
        assertEq(deal.tokenAddress, tokenAddress);
        assertEq(deal.amount, amount);
        assertEq(uint8(deal.status), uint8(TypesLib.Status.Pending));
        assertEq(deal.id, 0);

        // Check escrow balance;
        assertEq(address(bloomEscrow).balance, totalAmount);
    }

    function testCancelDeal() external {
        //  // Create a deal
          address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address tokenAddress = networkConfig.usdcTokenAddress;
        uint256 amount = 100e8;
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        // Mint some usdc to sender;
        IERC20Mock token = IERC20Mock(tokenAddress);
        vm.prank(address(helperConfig));
        token.mint(sender, 1_000_000e18);

        vm.startPrank(sender);
        // Approve bloom escrow to spend your token
        token.approve(address(bloomEscrow), totalAmount);
        bloomEscrow.createDeal(sender, receiver, tokenAddress, amount);
        vm.stopPrank();

        // // Cancel the deal

        // Determine balance before cancellation
        uint256 balanceBeforeCancel = token.balanceOf(sender);
        uint256 balanceBeforeCancelEscrow = token.balanceOf(address(bloomEscrow));

        // Expect this to fail
        vm.startPrank(receiver);
        vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotSender.selector));
        bloomEscrow.cancelDeal(0);
        vm.stopPrank();

        // Expect this to work
        vm.startPrank(sender);
        bloomEscrow.cancelDeal(0);
        vm.stopPrank();


        // Determine balance after cancellation
        uint256 balanceAfterCancel = token.balanceOf(sender);
        uint256 balanceAfterCancelEscrow = token.balanceOf(address(bloomEscrow));

        // Check states
        TypesLib.Deal memory deal = bloomEscrow.getDeal(0);
        assertEq(balanceBeforeCancel + amount, balanceAfterCancel);
        assertEq(balanceBeforeCancelEscrow - amount, balanceAfterCancelEscrow);
        assertEq(uint8(deal.status), uint8(TypesLib.Status.Canceled));

    }

    function testAcknowledgeDeal() external {
        // // Create a deal 
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address tokenAddress = networkConfig.usdcTokenAddress;
        uint256 amount = 100e8;
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        // Mint some usdc to sender;
        IERC20Mock token = IERC20Mock(tokenAddress);
        vm.prank(address(helperConfig));
        token.mint(sender, 1_000_000e18);

        vm.startPrank(sender);
        // Approve bloom escrow to spend your token
        token.approve(address(bloomEscrow), totalAmount);
        bloomEscrow.createDeal(sender, receiver, tokenAddress, amount);
        vm.stopPrank();

        // //  Receiver acknowledge the deal
        // Only the receiver should be able to acknowledge
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotReceiver.selector));
        bloomEscrow.acknowledgeDeal(0);
        vm.stopPrank();

        // Now acknowledge the deal
        vm.startPrank(receiver);
        bloomEscrow.acknowledgeDeal(0);
        vm.stopPrank();


        // // You should not be able to cancel a deal that has already been acknowledge.
        // Cancel the deal
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotSender.selector));
        bloomEscrow.cancelDeal(0);
        vm.stopPrank();
    }

}
