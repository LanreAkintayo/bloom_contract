// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployFeeController} from "../script/DeployFeeController.s.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {BaseJuror} from "./BaseJuror.t.sol";
import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";
import {TypesLib} from "../src/library/TypesLib.sol";
import {JurorManager} from "../src/core/disputes/JurorManager.sol";
import {DisputeStorage} from "../src/core/disputes/DisputeStorage.sol";

contract JurorManagerTest is BaseJuror {
    // ------------------------
    // Helper functions
    // ------------------------

    function _createERC20Deal(address _sender, address _receiver, address tokenAddress, uint256 amount)
        internal
        returns (uint256 dealId)
    {
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        IERC20Mock token = IERC20Mock(tokenAddress);
        vm.prank(address(helperConfig));
        token.mint(_sender, 1_000_000e18);

        vm.startPrank(_sender);
        token.approve(address(bloomEscrow), totalAmount);
        bloomEscrow.createDeal(_sender, _receiver, tokenAddress, amount);
        vm.stopPrank();

        return bloomEscrow.dealCount() - 1;
    }

    function _createETHDeal(address _sender, address _receiver, uint256 amount) internal returns (uint256 dealId) {
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        vm.deal(_sender, 100 ether);

        vm.startPrank(_sender);
        bloomEscrow.createDeal{value: totalAmount}(_sender, _receiver, address(0), amount);
        vm.stopPrank();

        return bloomEscrow.dealCount() - 1;
    }



    function _openDispute(address _sender, uint256 dealId) internal returns(uint256) {
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        address tokenAddress = deal.tokenAddress;
        IERC20Mock token = IERC20Mock(tokenAddress);
        uint256 dealAmount = deal.amount;
        uint256 disputeFee = feeController.calculateDisputeFee(dealAmount);

        vm.startPrank(_sender);
        token.approve(address(jurorManager), disputeFee);
        jurorManager.openDispute(dealId);
        vm.stopPrank();

        uint256 disputeId = jurorManager.dealToDispute(dealId);
        return disputeId;
    }

    function testJurorManagerDeployed() external view {
        assert(address(jurorManager) != address(0));
    }

    function testOpenDispute() external {
        // //  You should not be able to open dispute if you haven't create a deal in the first place

        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 100e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);

        // Then you should be able to open a dispute;
       uint256 disputeId = _openDispute(sender, dealId);

        // Then check the states;
        // DisputeStorage.Dispute memory dispute = jurorManager.disputes(disputeId);
        // assert(dispute.initiator == sender);
        // assert(dispute.dealId == dealId);
        // assert(dispute.sender == sender);
        // assert(dispute.receiver == receiver);
        // assert(dispute.winner == address(0));
    }

    function testShouldRegisterJuror() external {
        // You should be able to register a juror
        address juror1 = makeAddr("juror1");
        uint256 stakeAmount = 2000e18;

        // Mint to juror 1 and then approve the contract to spend the stake amount
        
        vm.prank(address(helperConfig));
        bloom.mint(juror1, stakeAmount);

        uint256 tokenBalanceBefore = bloom.balanceOf(juror1);


        // You can only stake with bloom token
        vm.startPrank(juror1);
        bloom.approve(address(jurorManager), stakeAmount);

        jurorManager.registerJuror(stakeAmount);
        vm.stopPrank();

        uint256 tokenBalanceAfter = bloom.balanceOf(juror1);
        assert(tokenBalanceBefore - tokenBalanceAfter == stakeAmount);

        // Then, check the states;
        assert(jurorManager.allJurorAddresses(0) == juror1);
        assert(jurorManager.activeJurorAddresses(0) == juror1);
        assert(jurorManager.jurorAddressIndex(juror1) == 0);

        JurorManager.Juror memory juror = jurorManager.getJuror(juror1);

        assert(juror.stakeAmount == stakeAmount);
        assert(juror.reputation == 0);
        assert(juror.jurorAddress == juror1);
        assert(juror.missedVotesCount == 0);
    }

    function testSelectJuror() external {
        uint256 disputeId;
        uint256 thresholdFP;
        uint256 alphaFP;
        uint256 betaFP;
        uint256 expNeeded;
        uint256 newbieNeeded;
        uint256 experiencedPoolSize;

        jurorManager.selectJurors(disputeId, thresholdFP, alphaFP, betaFP, expNeeded, newbieNeeded, experiencedPoolSize);
    }
}
