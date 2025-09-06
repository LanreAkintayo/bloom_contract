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
import {LinkToken} from "@chainlink/contracts/src/v0.8/shared/token/ERC677/LinkToken.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";



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

    function _openDispute(address _sender, uint256 dealId) internal returns (uint256) {
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
        uint256 alphaFP = 0.6e18; // Stake is stronger
        uint256 betaFP = 0.4e18; // Reputation is betaFP
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 3;
        uint256 expPoolSize;

        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);

        // Then you should be able to open a dispute;
        disputeId = _openDispute(sender, dealId);

        // Register some jurors
        address juror1 = _registerJuror(makeAddr("juror1"), 2000e18);
        address juror2 = _registerJuror(makeAddr("juror2"), 4000e18);
        address juror3 = _registerJuror(makeAddr("juror3"), 6000e18);
        address juror4 = _registerJuror(makeAddr("juror4"), 8000e18);
        address juror5 = _registerJuror(makeAddr("juror5"), 1500e18);
        address juror6 = _registerJuror(makeAddr("juror6"), 9000e18);

        // Get all active juror addresses
        address[] memory jurorAddresses = jurorManager.getActiveJurorAddresses();
        uint256 percentage = 6000; // Top 60% should be amongst the experienced. The remaining 40% will be with the newbies

        // Send LinkToken to the JurorManager contract
        LinkToken linkToken = LinkToken(networkConfig.linkAddress);
        vm.prank(address(helperConfig));
        linkToken.mint(address(jurorManager), 10000e18);

        (thresholdFP, expPoolSize) = getThresholdAndExpPoolSize(jurorAddresses, percentage, alphaFP, betaFP);

        // This function can only be called by the owner
        vm.prank(jurorManager.owner());
        uint256 requestId = jurorManager.selectJurors(disputeId, thresholdFP, alphaFP, betaFP, expNeeded, newbieNeeded, expPoolSize);

        // Then call fulfillRandomWords
        // uint256[] memory randomWords = new uint256[](randomWords.length);
        // randomWords[0] = 7854166079704491096882992406342334108369226379826116161446442989268089806461;

        // jurorManager.fulfillRandomWords(requestId, randomWords);
        // vm.stopPrank();
        
        // Can only be called by the deployer
        console.log("Calling fulfillRandomWords");
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(jurorManager));

    }

    function _registerJuror(address jurorAddress, uint256 stakeAmount) internal returns (address) {
        // Mint to the juror;
        vm.prank(address(helperConfig));
        bloom.mint(jurorAddress, stakeAmount);

        // You can only stake with bloom token
        vm.startPrank(jurorAddress);
        bloom.approve(address(jurorManager), stakeAmount);

        jurorManager.registerJuror(stakeAmount);
        vm.stopPrank();

        return jurorAddress;
    }

    // helper to compute score with fixed-point scaling (1e18)
    function _computeScore(address jurorAddress, uint256 maxStake, uint256 maxRep, uint256 alphaFP, uint256 betaFP)
        internal
        view
        returns (uint256)
    {
        JurorManager.Juror memory j = jurorManager.getJuror(jurorAddress);
        uint256 stakePart = (j.stakeAmount * 1e18) / maxStake;
        uint256 repPart = ((j.reputation + 1) * 1e18) / (maxRep + 1);
        return (alphaFP * stakePart + betaFP * repPart) / 1e18;

        // uint256 score = (alphaFP * j.stakeAmount / maxStake) + (betaFP * (j.reputation + 1) / (maxRep + 1));
        // return score;
    }

    /// @notice Given jurors and a percentage (like 60 for 60%). This percentage is like saying, top 60% jurors are experienced
    /// returns threshold and expPoolSize dynamically
    function getThresholdAndExpPoolSize(
        address[] memory jurorAddresses,
        uint256 percentage,
        uint256 alphaFP,
        uint256 betaFP
    ) internal view returns (uint256 thresholdFP, uint256 expPoolSize) {
        // Get all the jurors in an array
        JurorManager.Juror[] memory jurors = new JurorManager.Juror[](jurorAddresses.length);

        for (uint256 i = 0; i < jurorAddresses.length; i++) {
            jurors[i] = jurorManager.getJuror(jurorAddresses[i]);
        }

        uint256 jurorLength = jurors.length;

        assert(jurorLength > 0);

        // figure out maxStake and maxRep
        uint256 maxStake;
        uint256 maxRep;
        for (uint256 i = 0; i < jurorLength; i++) {
            if (jurors[i].stakeAmount > maxStake) maxStake = jurors[i].stakeAmount;
            if (jurors[i].reputation > maxRep) maxRep = jurors[i].reputation;
        }

        // compute scores
        uint256[] memory scores = new uint256[](jurorLength);
        for (uint256 i = 0; i < jurorLength; i++) {
            scores[i] = _computeScore(jurors[i].jurorAddress, maxStake, maxRep, alphaFP, betaFP);
        }

        // sort descending (naive bubble sort for test only)
        for (uint256 i = 0; i < jurorLength; i++) {
            for (uint256 j = i + 1; j < jurorLength; j++) {
                if (scores[j] > scores[i]) {
                    (scores[i], scores[j]) = (scores[j], scores[i]);
                }
            }
        }

        expPoolSize = (jurorLength * percentage) / 10_000; // 100% = 10,000
        if (expPoolSize == 0) {
            return (type(uint256).max, 0); // means no experienced
        }

        uint256 sExp = scores[expPoolSize - 1]; // sExp is the last person in the experienced pool
        if (expPoolSize < jurorLength) {
            uint256 sNext = scores[expPoolSize]; // sNext is the person that follows the last person outside of the experienced pool
            if (sExp > sNext) {
                thresholdFP = (sExp + sNext) / 2;
            } else {
                // tie case, include all with score >= sExp
                thresholdFP = sExp;
                uint256 count = 0;
                for (uint256 i = 0; i < jurorLength; i++) {
                    if (scores[i] >= thresholdFP) count++;
                }
                expPoolSize = count;
            }
        } else {
            // everyone is experienced
            thresholdFP = 0;
        }
    }
}
