// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;


// import {Test, console} from "forge-std/Test.sol";
// import {DeployBloomEscrow} from "../script/deploy/DeployBloomEscrow.s.sol";
// import {BloomEscrow} from "../src/core/escrow/BloomEscrow.sol";
// import {Bloom} from "../src/token/Bloom.sol";
// import {HelperConfig} from "../script/HelperConfig.s.sol";
// import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";
// import {FeeController} from "../src/core/FeeController.sol";
// import {DeployFeeController} from "../script/deploy/DeployFeeController.s.sol";
// import {TypesLib} from "../src/library/TypesLib.sol";

// contract BloomEscrowTest is Test {
//     DeployBloomEscrow deployBloomEscrow;
//     DeployFeeController deployFeeController;
//     BloomEscrow bloomEscrow;
//     HelperConfig helperConfig;
//     HelperConfig.NetworkConfig networkConfig;
//     FeeController feeController;

//     address sender;
//     address receiver;

//     function setUp() external {
//         // Deploy contracts
        
//         deployBloomEscrow = new DeployBloomEscrow();
//         (bloomEscrow, helperConfig) = deployBloomEscrow.run();
//         networkConfig = helperConfig.getConfigByChainId(block.chainid);
        
//         deployFeeController = new DeployFeeController();
//         (feeController, ) = deployFeeController.run();
//         networkConfig = helperConfig.getConfigByChainId(block.chainid);

//         // Link fee controller
//         vm.startPrank(bloomEscrow.owner());
//         bloomEscrow.addFeeController(address(feeController));
//         bloomEscrow.addToken(networkConfig.usdcTokenAddress);
//         bloomEscrow.addToken(networkConfig.daiTokenAddress);
//         bloomEscrow.addToken(networkConfig.wethTokenAddress);
//         vm.stopPrank();

//         // Configure fee controller
//         vm.startPrank(feeController.owner());
//         feeController.addToDataFeed(networkConfig.usdcTokenAddress, networkConfig.usdcUsdPriceFeed);
//         feeController.addToDataFeed(networkConfig.daiTokenAddress, networkConfig.daiUsdPriceFeed);
//         feeController.addToDataFeed(networkConfig.wethTokenAddress, networkConfig.ethUsdPriceFeed);
//         vm.stopPrank();

//         // Test actors
//         sender = makeAddr("sender");
//         receiver = makeAddr("receiver");
//     }

//     // ------------------------
//     // Helper functions
//     // ------------------------


//     // In your smart contract

//     function _createERC20Deal(address _sender, address _receiver, address tokenAddress, uint256 amount, string memory description)
//         internal
//         returns (uint256 dealId)
//     {
//         uint256 escrowFee = feeController.calculateEscrowFee(amount);
//         uint256 totalAmount = amount + escrowFee;

//         IERC20Mock token = IERC20Mock(tokenAddress);
//         vm.prank(address(helperConfig));
//         token.mint(_sender, 1_000_000e18);

//         vm.startPrank(_sender);
//         token.approve(address(bloomEscrow), totalAmount);
//         bloomEscrow.createDeal(_sender, _receiver, tokenAddress, amount, description);
//         vm.stopPrank();

//         return bloomEscrow.dealCount() - 1;
//     }

//     function _createETHDeal(address _sender, address _receiver, uint256 amount, string memory description) internal returns (uint256 dealId) {
//         uint256 escrowFee = feeController.calculateEscrowFee(amount);
//         uint256 totalAmount = amount + escrowFee;

//         vm.deal(_sender, 100 ether);

//         vm.startPrank(_sender);
//         console.log("Network.wethTokenAddress: ", networkConfig.wethTokenAddress);
//         console.log("Network.wrappedTokenAddress: ", networkConfig.wrappedNativeTokenAddress);
//         bloomEscrow.createDeal{value: totalAmount}(_sender, _receiver, networkConfig.wethTokenAddress, amount, description);
//         vm.stopPrank();

//         return bloomEscrow.dealCount() - 1;
//     }

//     function _assertDeal(
//         TypesLib.Deal memory deal,
//         address expectedSender,
//         address expectedReceiver,
//         address expectedToken,
//         uint256 expectedAmount,
//         TypesLib.Status expectedStatus
//     ) internal pure {
//         assertEq(deal.sender, expectedSender);
//         assertEq(deal.receiver, expectedReceiver);
//         assertEq(deal.tokenAddress, expectedToken);
//         assertEq(deal.amount, expectedAmount);
//         assertEq(uint8(deal.status), uint8(expectedStatus));
//     }

//     // ------------------------
//     // Tests
//     // ------------------------

//     function testCreateDealWithERC20() external {
//         uint256 amount = 100e8;
//         string memory description = "Test deal";
//         uint256 dealId = _createERC20Deal(sender, receiver, networkConfig.usdcTokenAddress, amount, description);

//         TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);
//         _assertDeal(deal, sender, receiver, networkConfig.usdcTokenAddress, amount, TypesLib.Status.Pending);

//         uint256 escrowFee = feeController.calculateEscrowFee(amount);
//         assertEq(IERC20Mock(networkConfig.usdcTokenAddress).balanceOf(address(bloomEscrow)), amount + escrowFee);
//     }

//     function testCreateDealWithETH() external {
//         uint256 amount = 10e8;
//         string memory description = "Test deal with ETH";
//         uint256 dealId = _createETHDeal(sender, receiver, amount, description);

//         TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);
//         _assertDeal(deal, sender, receiver, networkConfig.wethTokenAddress, amount, TypesLib.Status.Pending);

//         uint256 escrowFee = feeController.calculateEscrowFee(amount);
//         assertEq(address(bloomEscrow).balance, amount + escrowFee);
//     }

//     function testCancelDeal() external {
//         string memory description = "Test cancel deal";
//         uint256 dealId = _createERC20Deal(sender, receiver, networkConfig.usdcTokenAddress, 100e8, description);
//         IERC20Mock token = IERC20Mock(networkConfig.usdcTokenAddress);

//         // Receiver cannot cancel
//         vm.startPrank(receiver);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotSender.selector));
//         bloomEscrow.cancelDeal(dealId);
//         vm.stopPrank();

//         // Sender cancels
//         uint256 balanceBefore = token.balanceOf(sender);
//         vm.startPrank(sender);
//         bloomEscrow.cancelDeal(dealId);
//         vm.stopPrank();

//         TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);
//         assertEq(token.balanceOf(sender), balanceBefore + deal.amount);
//         _assertDeal(deal, sender, receiver, networkConfig.usdcTokenAddress, deal.amount, TypesLib.Status.Canceled);
//     }

//     function testAcknowledgeDeal() external {
//         string memory description = "Test acknowledge deal";
//         uint256 dealId = _createERC20Deal(sender, receiver, networkConfig.usdcTokenAddress, 100e8, description);

//         // Only receiver can acknowledge
//         vm.startPrank(sender);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotReceiver.selector));
//         bloomEscrow.acknowledgeDeal(dealId);
//         vm.stopPrank();

//         vm.startPrank(receiver);
//         bloomEscrow.acknowledgeDeal(dealId);
//         vm.stopPrank();

//         // Cannot cancel after acknowledgement
//         vm.startPrank(sender);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotPending.selector));
//         bloomEscrow.cancelDeal(dealId);
//         vm.stopPrank();
//     }

//     function testUnacknowledgeDeal() external {
//         string memory description = "Test unacknowledge deal";
//         uint256 dealId = _createERC20Deal(sender, receiver, networkConfig.usdcTokenAddress, 100e8, description);

//         // Receiver acknowledges
//         vm.startPrank(receiver);
//         bloomEscrow.acknowledgeDeal(dealId);
//         vm.stopPrank();

//         // Sender cannot cancel while acknowledged
//         vm.startPrank(sender);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__NotPending.selector));
//         bloomEscrow.cancelDeal(dealId);
//         vm.stopPrank();

//         // Receiver unacknowledges
//         vm.startPrank(receiver);
//         bloomEscrow.unacknowledgeDeal(dealId);
//         vm.stopPrank();

//         // Sender can cancel now
//         vm.startPrank(sender);
//         bloomEscrow.cancelDeal(dealId);
//         vm.stopPrank();
//     }

//     function testFinalizeDealWithERC20() external {
//         // The sender will finalize deal after they are done with their transactions with the receivers;
//         string memory description = "Test finalize deal";
//         uint256 dealId = _createERC20Deal(sender, receiver, networkConfig.usdcTokenAddress, 100e8, description);

//         // Check balance of receiver before finalizing;
//         IERC20Mock token = IERC20Mock(networkConfig.usdcTokenAddress);
//         uint256 balanceBefore = token.balanceOf(receiver);

//         // Then finalize later even if the receiver has not acknowledge;
//         vm.startPrank(sender);
//         bloomEscrow.finalizeDeal(dealId);
//         vm.stopPrank();

//         // Check balance of receiver after finalizing;
//         uint256 balanceAfter = token.balanceOf(receiver);

//         assertEq(balanceAfter, balanceBefore + 100e8);

//         // After finalizing, make sure that you cannot finalize again
//         vm.startPrank(sender);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__AlreadyFinalized.selector));
//         bloomEscrow.finalizeDeal(dealId);
//         vm.stopPrank();

//     }

//      function testFinalizeDealAfterAcknowledgeWithERC20() external {
//         // The sender will finalize deal after they are done with their transactions with the receivers;

//         string memory description = "Test finalize deal after acknowledge";
//         uint256 dealId = _createERC20Deal(sender, receiver, networkConfig.usdcTokenAddress, 100e8, description);

//         // Receiver acknowledges;
//         vm.startPrank(receiver);
//         bloomEscrow.acknowledgeDeal(dealId);
//         vm.stopPrank();

//         // Check balance of receiver before finalizing;
//         IERC20Mock token = IERC20Mock(networkConfig.usdcTokenAddress);
//         uint256 balanceBefore = token.balanceOf(receiver);

//         // Then finalize later
//         vm.startPrank(sender);
//         bloomEscrow.finalizeDeal(dealId);
//         vm.stopPrank();

//         // Check balance of receiver after finalizing;
//         uint256 balanceAfter = token.balanceOf(receiver);

//         assertEq(balanceAfter, balanceBefore + 100e8);

//         // After finalizing, make sure that you cannot finalize again
//         vm.startPrank(sender);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__AlreadyFinalized.selector));
//         bloomEscrow.finalizeDeal(dealId);
//         vm.stopPrank();

//     }

//     function testFinalizeDealWithETH() external {
//         // The sender will finalize deal after they are done with their transactions with the receivers;
//         string memory description = "Test finalize deal with ETH";
//         uint256 dealId = _createETHDeal(sender, receiver, 100e8, description);

//         // Check balance of receiver before finalizing;
//         uint256 balanceBefore = receiver.balance;

//         // Then finalize later even if the receiver has not acknowledge;
//         vm.startPrank(sender);
//         bloomEscrow.finalizeDeal(dealId);
//         vm.stopPrank();

//         // Check balance of receiver after finalizing;
//         uint256 balanceAfter = receiver.balance;

//         assertEq(balanceAfter, balanceBefore + 100e8);

//         // After finalizing, make sure that you cannot finalize again
//         vm.startPrank(sender);
//         vm.expectRevert(abi.encodeWithSelector(BloomEscrow.BloomEscrow__AlreadyFinalized.selector));
//         bloomEscrow.finalizeDeal(dealId);
//         vm.stopPrank();
//     }
// }
