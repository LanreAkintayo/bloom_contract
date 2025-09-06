// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployFeeController} from "../script/DeployFeeController.s.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {BaseJuror} from "./BaseJuror.t.sol";
import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";

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

    function testJurorManagerDeployed() external view {
        assert(address(jurorManager) != address(0));
    }

    function testOpenDispute() external {
        // //  You should not be able to open dispute if you haven't create a deal in the first place

        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        IERC20Mock daiToken = IERC20Mock(daiTokenAddress);
        uint256 dealAmount = 100e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);

        // Then you should be able to open a dispute;
        // approve dispute fee;
        uint256 disputeFee = feeController.calculateDisputeFee(dealAmount);
        assertEq(disputeFee, 5e18);
        
        vm.startPrank(sender);
        daiToken.approve(address(jurorManager), disputeFee);
        jurorManager.openDispute(dealId);
        vm.stopPrank();

        // Then check the states;
    }


    function testSelectJuror() external {

    }
}


