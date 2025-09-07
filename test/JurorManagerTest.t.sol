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
import {VRFV2Wrapper} from "@chainlink/contracts/src/v0.8/vrf/VRFV2Wrapper.sol";
import {DisputeManager} from "../src/core/disputes/DisputeManger.sol";

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

    function _selectJurors(uint256 _disputeId, uint256 expNeeded, uint256 newbieNeeded) internal {
        uint256 thresholdFP;
        uint256 alphaFP = 0.6e18; // Stake is stronger
        uint256 betaFP = 0.4e18; // Reputation is betaFP
        uint256 expPoolSize;
        // Get all active juror addresses
        address[] memory jurorAddresses = jurorManager.getActiveJurorAddresses();
        uint256 percentage = 8000; // Top 80% should be amongst the experienced. The remaining 40% will be with the newbies

        // Send LinkToken to the JurorManager contract
        LinkToken linkToken = LinkToken(networkConfig.linkAddress);
        vm.prank(address(helperConfig));
        linkToken.mint(address(jurorManager), 10000e18);

        (thresholdFP, expPoolSize) = getThresholdAndExpPoolSize(jurorAddresses, percentage, alphaFP, betaFP);

        // This function can only be called by the owner
        vm.prank(jurorManager.owner());
        uint256 requestId =
            jurorManager.selectJurors(_disputeId, thresholdFP, alphaFP, betaFP, expNeeded, newbieNeeded, expPoolSize);

        // Then call fulfillRandomWords
        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));
    }

    function _vote(uint256 _disputeId, address _jurorAddress, address support)
        internal
        returns (JurorManager.Vote memory)
    {
        vm.prank(_jurorAddress);
        jurorManager.vote(_disputeId, support);

        return jurorManager.getDisputeVote(_disputeId, _jurorAddress);
    }

    function _assertVote(
        JurorManager.Vote memory vote,
        address _jurorAddress,
        uint256 _disputeId,
        uint256 _dealId,
        address support
    ) internal pure {
        assertEq(vote.jurorAddress, _jurorAddress);
        assertEq(vote.disputeId, _disputeId);
        assertEq(vote.dealId, _dealId);
        assertEq(vote.support, support);
    }

    function _assertCandidate(
        JurorManager.Candidate memory candidate,
        uint256 _disputeId,
        address _jurorAddress,
        uint256 _stakeAmount,
        uint256 _reputation,
        uint256 _score,
        bool _missed,
        bool checkMissed
    ) internal pure {
        if (_disputeId != type(uint256).max) {
            assertEq(candidate.disputeId, _disputeId);
        }
        if (_jurorAddress != address(0)) {
            assertEq(candidate.jurorAddress, _jurorAddress);
        }
        if (_stakeAmount != type(uint256).max) {
            assertEq(candidate.stakeAmount, _stakeAmount);
        }
        if (_reputation != type(uint256).max) {
            assertEq(candidate.reputation, _reputation);
        }
        if (_score != type(uint256).max) {
            assertEq(candidate.score, _score);
        }
        // missed: since it's bool, you can add another param to decide if to check
        if (checkMissed) {
            assertEq(candidate.missed, _missed);
        }
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
        uint256 requestId =
            jurorManager.selectJurors(disputeId, thresholdFP, alphaFP, betaFP, expNeeded, newbieNeeded, expPoolSize);

        // Then call fulfillRandomWords
        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));

        // Check states;
        // Let's use juror 1
        uint256[] memory jurorHistory = jurorManager.getJurorDisputeHistory(juror1);
        assertEq(jurorHistory[0], disputeId);
        assertEq(jurorManager.ongoingDisputeCount(juror1), 1);
        address[] memory disputeJurors = jurorManager.getDisputeJurors(disputeId);
        assertEq(disputeJurors.length, newbieNeeded + expNeeded);
        JurorManager.Candidate memory candidate = jurorManager.getDisputeCandidate(disputeId, juror1);
        assertEq(candidate.stakeAmount, 2000e18);
    }

    function testCanVote() external {
        uint256 disputeId;
        uint256 thresholdFP;
        uint256 alphaFP = 0.6e18; // Stake is stronger
        uint256 betaFP = 0.4e18; // Reputation is betaFP
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;
        uint256 expPoolSize;

        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);

        // Then you should be able to open a dispute;
        disputeId = _openDispute(sender, dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        address juror6 = _registerJuror(makeAddr("juror6"), 9000e18);

        // Get all active juror addresses
        address[] memory jurorAddresses = jurorManager.getActiveJurorAddresses();
        uint256 percentage = 8000; // Top 80% should be amongst the experienced. The remaining 40% will be with the newbies

        // Send LinkToken to the JurorManager contract
        LinkToken linkToken = LinkToken(networkConfig.linkAddress);
        vm.prank(address(helperConfig));
        linkToken.mint(address(jurorManager), 10000e18);

        (thresholdFP, expPoolSize) = getThresholdAndExpPoolSize(jurorAddresses, percentage, alphaFP, betaFP);

        // This function can only be called by the owner
        vm.prank(jurorManager.owner());
        uint256 requestId =
            jurorManager.selectJurors(disputeId, thresholdFP, alphaFP, betaFP, expNeeded, newbieNeeded, expPoolSize);

        // Then call fulfillRandomWords
        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = jurorManager.getDisputeJurors(disputeId);

        // Get the dispute itself;
        JurorManager.Dispute memory dispute = jurorManager.getDispute(disputeId);

        // Assert candidates;
        JurorManager.Candidate memory candidate0 = jurorManager.getDisputeCandidate(disputeId, disputeJurors[0]);
        JurorManager.Candidate memory candidate1 = jurorManager.getDisputeCandidate(disputeId, disputeJurors[1]);
        JurorManager.Candidate memory candidate2 = jurorManager.getDisputeCandidate(disputeId, disputeJurors[2]);

        _assertCandidate(
            candidate0,
            disputeId,
            disputeJurors[0],
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            false,
            false
        );
        _assertCandidate(
            candidate1,
            disputeId,
            disputeJurors[1],
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            false,
            false
        );
        _assertCandidate(
            candidate2,
            disputeId,
            disputeJurors[2],
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            false,
            false
        );

        // Juros can vote;
        JurorManager.Vote memory vote0 = _vote(disputeId, disputeJurors[0], dispute.sender);
        JurorManager.Vote memory vote1 = _vote(disputeId, disputeJurors[1], dispute.receiver);
        JurorManager.Vote memory vote2 = _vote(disputeId, disputeJurors[2], dispute.sender);

        // Revert if disputeJurors0 tries to vote again;
        vm.startPrank(disputeJurors[0]);
        vm.expectRevert(abi.encodeWithSelector(JurorManager.JurorManager__AlreadyVoted.selector));
        jurorManager.vote(disputeId, dispute.receiver);
        vm.stopPrank();

        // Revert if someone that is not chosen tries to vote;
        vm.startPrank(juror6);
        vm.expectRevert(abi.encodeWithSelector(JurorManager.JurorManager__NotEligible.selector));
        jurorManager.vote(disputeId, sender);
        vm.stopPrank();

        // Check to see if votes are registered perfectly.
        _assertVote(vote0, disputeJurors[0], disputeId, dealId, dispute.sender);
        _assertVote(vote1, disputeJurors[1], disputeId, dealId, dispute.receiver);
        _assertVote(vote2, disputeJurors[2], disputeId, dealId, dispute.sender);
    }

    function testCanFinishDispute() external {
        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Then you should be able to open a dispute;
        uint256 disputeId = _openDispute(sender, dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 9000e18);

        // Select Jurors
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;
        _selectJurors(disputeId, expNeeded, newbieNeeded);

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = jurorManager.getDisputeJurors(disputeId);

        // Get the dispute itself;
        JurorManager.Dispute memory dispute = jurorManager.getDispute(disputeId);

        // Juros can vote;
        address disputeJuror1 = disputeJurors[0];
        address disputeJuror2 = disputeJurors[1];
        address disputeJuror3 = disputeJurors[2];

        _vote(disputeId, disputeJuror1, dispute.sender);
        _vote(disputeId, disputeJuror2, dispute.receiver);
        _vote(disputeId, disputeJuror3, dispute.sender);

        JurorManager.Juror memory juror1Before = jurorManager.getJuror(disputeJuror1);
        JurorManager.Juror memory juror2Before = jurorManager.getJuror(disputeJuror2);
        JurorManager.Juror memory juror3Before = jurorManager.getJuror(disputeJuror3);

        // Should fail because voting time has not elapsed;
        vm.startPrank(jurorManager.owner());
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__NotFinished.selector));
        jurorManager.finishDispute(disputeId);
        vm.stopPrank();

        // Fast forward time;
        vm.warp(block.timestamp + 48 hours);

        // Finish dispute;
        vm.startPrank(jurorManager.owner());
        jurorManager.finishDispute(disputeId);
        vm.stopPrank();

        // // Check states;

        // Make sure that the Dispute itself has been updated to reflect the new winnner.
        assertEq(jurorManager.getDispute(disputeId).winner, dispute.sender);

        // Check to see that the reputation and stake amount of the people voted winner have updated accordingly.
        JurorManager.Juror memory juror1After = jurorManager.getJuror(disputeJuror1);
        JurorManager.Juror memory juror2After = jurorManager.getJuror(disputeJuror2);
        JurorManager.Juror memory juror3After = jurorManager.getJuror(disputeJuror3);

        assertGt(juror1After.reputation, juror1Before.reputation);
        assertGt(juror1After.stakeAmount, juror1Before.stakeAmount);

        assertEq(juror2After.reputation, 0);
        assertLt(juror2After.stakeAmount, juror2Before.stakeAmount);

        assertGt(juror3After.reputation, juror3Before.reputation);
        assertGt(juror3After.stakeAmount, juror3Before.stakeAmount);

        // Trying to relase funds before the appeal period;
         // Winner cannot pull out funds because there is still a room for apeal
        vm.startPrank(dispute.sender);
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__AppealTime.selector));
        jurorManager.releaseFundsToWinner(disputeId);
        vm.stopPrank();

        // Fast forward to after appeal period;
        vm.warp(block.timestamp + jurorManager.appealDuration());


        // Loser cannot call releaseFundsToWinner
        vm.startPrank(dispute.receiver);
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__OnlyWinner.selector));
        jurorManager.releaseFundsToWinner(disputeId);
        vm.stopPrank();

        // Check the balance of the winner before funds is released;
         IERC20Mock token = IERC20Mock(deal.tokenAddress);
        uint256 winnerTokenBalanceBefore = token.balanceOf(dispute.sender);

        // Release funds to winner
        vm.startPrank(dispute.sender);
        jurorManager.releaseFundsToWinner(disputeId);
        vm.stopPrank();

        uint256 winnerTokenBalanceAfter = token.balanceOf(dispute.sender);

        assertEq(winnerTokenBalanceAfter, winnerTokenBalanceBefore + deal.amount);


        // Check the balance of the winner after funds have been released

        // console.log("Stake amount of juror 1 before: ", juror1Before.stakeAmount);
        // console.log("Stake amount of juror 1 after: ", juror1After.stakeAmount);
        // console.log("Difference in stake of juror 1: ", juror1After.stakeAmount - juror1Before.stakeAmount);

        // console.log("Reputation of juror 1 before: ", juror1Before.reputation);
        // console.log("Reputation of juror 1 after: ", juror1After.reputation);
        // console.log("Difference in reputation of juror 1: ", juror1After.reputation - juror1Before.reputation);

        // console.log("Stake amount of juror 2 before: ", juror2Before.stakeAmount);
        // console.log("Stake amount of juror 2 after: ", juror2After.stakeAmount);
        // console.log("Difference in stake of juror 2: ", juror2Before.stakeAmount - juror2After.stakeAmount);

        // console.log("Reputation of juror 2 before: ", juror2Before.reputation);
        // console.log("Reputation of juror 2 after: ", juror2After.reputation);

        // console.log("Stake amount of juror 3 before: ", juror3Before.stakeAmount);
        // console.log("Stake amount of juror 3 after: ", juror3After.stakeAmount);
        // console.log("Difference in stake of juror 3: ", juror3After.stakeAmount - juror3Before.stakeAmount);

        // console.log("Reputation of juror 3 before: ", juror3Before.reputation);
        // console.log("Reputation of juror 3 after: ", juror3After.reputation);
    }

    function testCanAppeal() external {
        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Then you should be able to open a dispute;
        uint256 disputeId = _openDispute(sender, dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 9000e18);

        // Select Jurors
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;
        _selectJurors(disputeId, expNeeded, newbieNeeded);

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = jurorManager.getDisputeJurors(disputeId);

        // Get the dispute itself;
        JurorManager.Dispute memory dispute = jurorManager.getDispute(disputeId);

        // Juros can vote;
        address disputeJuror1 = disputeJurors[0];
        address disputeJuror2 = disputeJurors[1];
        address disputeJuror3 = disputeJurors[2];

        _vote(disputeId, disputeJuror1, dispute.sender);
        _vote(disputeId, disputeJuror2, dispute.receiver);
        _vote(disputeId, disputeJuror3, dispute.sender);

        // Fast forward time;
        vm.warp(block.timestamp + 48 hours);

        // Finish dispute;
        vm.startPrank(jurorManager.owner());
        jurorManager.finishDispute(disputeId);
        vm.stopPrank();


        // Fast forward to after appeal period;
        vm.warp(block.timestamp + jurorManager.appealDuration());


        // Loser appealing
        uint256 firstRound = 2;
        uint256 appealFee = feeController.calculateAppealFee(deal.tokenAddress, deal.amount, firstRound);

        IERC20Mock token = IERC20Mock(deal.tokenAddress);

        // Mint to the loser
        vm.prank(address(helperConfig));
        token.mint(dispute.receiver, appealFee);

        // Then the loser seeks for appeal;
        vm.startPrank(dispute.receiver);
        token.approve(address(jurorManager), appealFee);

        // Loser should not be able to make appeal because appeal period has passed;
        uint256 appealId = jurorManager.appeal(disputeId);
        vm.stopPrank();


        // // Check the states after appeal;
        // Check whether the dispute id has been linked to the new appeal
        uint256[] memory disputeAppeals = jurorManager.getDisputeAppeals(disputeId);
        assertEq(disputeAppeals[0], appealId);

        // Check whether the count has ben updated;
        uint256 disputeAppealCount = jurorManager.appealCounts(disputeId);
        assertEq(disputeAppealCount, 1);
    }

    function testCanAppealTwice() external {

        // Appeal two times and then finish dispute
        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Then you should be able to open a dispute;
        uint256 disputeId = _openDispute(sender, dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 9000e18);

        // Select Jurors
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;
        _selectJurors(disputeId, expNeeded, newbieNeeded);

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = jurorManager.getDisputeJurors(disputeId);

        // Get the dispute itself;
        JurorManager.Dispute memory dispute = jurorManager.getDispute(disputeId);

        // Juros can vote;
        address disputeJuror1 = disputeJurors[0];
        address disputeJuror2 = disputeJurors[1];
        address disputeJuror3 = disputeJurors[2];

        _vote(disputeId, disputeJuror1, dispute.sender);
        _vote(disputeId, disputeJuror2, dispute.receiver);
        _vote(disputeId, disputeJuror3, dispute.sender);

        // Fast forward time;
        vm.warp(block.timestamp + 48 hours);

        // Finish dispute;
        vm.startPrank(jurorManager.owner());
        jurorManager.finishDispute(disputeId);
        vm.stopPrank();


        // Fast forward to after appeal period;
        vm.warp(block.timestamp + jurorManager.appealDuration());


        // Loser appealing
        uint256 firstRound = 2;
        uint256 appealFee = feeController.calculateAppealFee(deal.tokenAddress, deal.amount, firstRound);

        IERC20Mock token = IERC20Mock(deal.tokenAddress);

        // Mint to the loser
        vm.prank(address(helperConfig));
        token.mint(dispute.receiver, appealFee);

        // Then the loser seeks for appeal;
        vm.startPrank(dispute.receiver);
        token.approve(address(jurorManager), appealFee);

        // Loser should not be able to make appeal because appeal period has passed;
        uint256 appealId = jurorManager.appeal(disputeId);
        vm.stopPrank();

        // Now, we repeat everything again.
        // Select Jurors
        uint256 expNeeded2 = 3;
        uint256 newbieNeeded2 = 2;
        _selectJurors(appealId, expNeeded2, newbieNeeded2);

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors2 = jurorManager.getDisputeJurors(appealId);

        // Get the appeal dispute itself;
        // Get corresponding disputeId for the appeal
        // uint256 correspondingDisputeId = jurorManager.appealToDispute(appealId);
        JurorManager.Dispute memory appealDispute = jurorManager.getDispute(appealId);

        // Juros can vote;
        address appealDisputeJuror1 = disputeJurors2[0];
        address appealDisputeJuror2 = disputeJurors2[1];
        address appealDisputeJuror3 = disputeJurors2[2];
        address appealDisputeJuror4 = disputeJurors2[3];
        address appealDisputeJuror5 = disputeJurors2[4];

        _vote(appealId, appealDisputeJuror1, appealDispute.sender);
        _vote(appealId, appealDisputeJuror2, appealDispute.receiver);
        _vote(appealId, appealDisputeJuror3, appealDispute.sender);
        _vote(appealId, appealDisputeJuror4, appealDispute.sender);
        _vote(appealId, appealDisputeJuror5, appealDispute.sender);
  

        // Fast forward time;
        vm.warp(block.timestamp + 48 hours);

        // Finish dispute;
        vm.startPrank(jurorManager.owner());
        jurorManager.finishDispute(appealId);
        vm.stopPrank();

        // Then the last winner withdraws;
          // Trying to relase funds before the appeal period;
         // Winner cannot pull out funds because there is still a room for apeal
        vm.startPrank(appealDispute.sender);
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__AppealTime.selector));
        jurorManager.releaseFundsToWinner(appealId);
        vm.stopPrank();

        // Fast forward to after appeal period;
        vm.warp(block.timestamp + jurorManager.appealDuration());


        // Loser cannot call releaseFundsToWinner
        vm.startPrank(appealDispute.receiver);
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__OnlyWinner.selector));
        jurorManager.releaseFundsToWinner(appealId);
        vm.stopPrank();

        // Check the balance of the winner before funds is released;
        uint256 winnerTokenBalanceBefore = token.balanceOf(appealDispute.sender);

        // Release funds to winner
        vm.startPrank(appealDispute.sender);
        jurorManager.releaseFundsToWinner(appealId);
        vm.stopPrank();

        uint256 winnerTokenBalanceAfter = token.balanceOf(appealDispute.sender);

        assertEq(winnerTokenBalanceAfter, winnerTokenBalanceBefore + deal.amount);



    }

    // function test

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
