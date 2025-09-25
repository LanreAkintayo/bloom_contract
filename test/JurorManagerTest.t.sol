// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployFeeController} from "../script/deploy/DeployFeeController.s.sol";
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
import {DisputeManager} from "../src/core/disputes/DisputeManager.sol";

contract JurorManagerTest is BaseJuror {
    // ------------------------
    // Helper functions
    // ------------------------

    function _createERC20Deal(
        address _sender,
        address _receiver,
        address tokenAddress,
        uint256 amount,
        string memory description
    ) internal returns (uint256 dealId) {
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        IERC20Mock token = IERC20Mock(tokenAddress);
        vm.prank(address(helperConfig));
        token.mint(_sender, 1_000_000e18);

        vm.startPrank(_sender);
        token.approve(address(bloomEscrow), totalAmount);
        bloomEscrow.createDeal(_sender, _receiver, tokenAddress, amount, description);
        vm.stopPrank();

        return bloomEscrow.dealCount() - 1;
    }

    function _createETHDeal(address _sender, address _receiver, uint256 amount, string memory description)
        internal
        returns (uint256 dealId)
    {
        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        uint256 totalAmount = amount + escrowFee;

        vm.deal(_sender, 100 ether);

        vm.startPrank(_sender);
        bloomEscrow.createDeal{value: totalAmount}(_sender, _receiver, address(0), amount, description);
        vm.stopPrank();

        return bloomEscrow.dealCount() - 1;
    }

    function _openDispute(address _sender, uint256 dealId, string memory description)
        internal
        returns (uint256, uint256)
    {
        // Send LinkToken to the JurorManager contract
        LinkToken linkToken = LinkToken(networkConfig.linkAddress);
        vm.prank(address(helperConfig));
        linkToken.mint(address(jurorManager), 10000e18);

        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        address tokenAddress = deal.tokenAddress;
        IERC20Mock token = IERC20Mock(tokenAddress);
        uint256 dealAmount = deal.amount;
        uint256 disputeFee = feeController.calculateDisputeFee(dealAmount);

        vm.startPrank(_sender);
        token.approve(address(disputeManager), disputeFee);
        (uint256 disputeId, uint256 requestId) = disputeManager.openDispute(dealId, description);
        vm.stopPrank();

        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));

        // uint256 disputeId = disputeStorage.dealToDispute(dealId);
        return (disputeId, requestId);
    }

    // function _selectJurors(uint256 _disputeId, uint256 expNeeded, uint256 newbieNeeded) internal {
    //     uint256 thresholdFP;
    //     uint256 alphaFP = 0.6e18; // Stake is stronger
    //     uint256 betaFP = 0.4e18; // Reputation is betaFP
    //     uint256 expPoolSize;
    //     // Get all active juror addresses
    //     address[] memory jurorAddresses = disputeStorage.getActiveJurorAddresses();
    //     uint256 percentage = 8000; // Top 80% should be amongst the experienced. The remaining 40% will be with the newbies

    //     // Send LinkToken to the JurorManager contract
    //     LinkToken linkToken = LinkToken(networkConfig.linkAddress);
    //     vm.prank(address(helperConfig));
    //     linkToken.mint(address(jurorManager), 10000e18);

    //     (thresholdFP, expPoolSize) = getThresholdAndExpPoolSize(jurorAddresses, percentage, alphaFP, betaFP);

    //     // This function can only be called by the owner
    //     vm.prank(jurorManager.owner());
    //     // uint256 requestId =
    //     //     jurorManager.selectJurors(_disputeId, thresholdFP, alphaFP, betaFP, expNeeded, newbieNeeded, expPoolSize);
    //     uint256 requestId = 1;

    //     // Then call fulfillRandomWords
    //     VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
    //     VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
    //     vm.prank(address(helperConfig));
    //     vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));
    // }

    function _vote(uint256 _disputeId, address _jurorAddress, address support)
        internal
        returns (TypesLib.Vote memory)
    {
        vm.prank(_jurorAddress);
        jurorManager.vote(_disputeId, support);

        return disputeStorage.getDisputeVote(_disputeId, _jurorAddress);
    }

    function _voteFlow(uint256 disputeId, address[] memory jurors, address[] memory votes) internal {
        // votes[i] is the party the juror votes for
        for (uint256 i = 0; i < votes.length; i++) {
            _vote(disputeId, jurors[i], votes[i]);
        }

        vm.warp(block.timestamp + disputeStorage.votingPeriod() + 1 hours);
        vm.startPrank(disputeManager.owner());
        //uncomment //uncomment disputeManager.finishDispute(disputeId);
        vm.stopPrank();
    }

    function _appealFlow(
        uint256 parentDisputeId,
        address loser,
        IERC20Mock token,
        uint256 amount,
        uint256 round,
        string memory description
    ) internal returns (uint256, uint256) {
        uint256 appealFee = feeController.calculateAppealFee(address(token), amount, round);

        // fund loser
        vm.prank(address(helperConfig));
        token.mint(loser, appealFee);

        vm.startPrank(loser);
        token.approve(address(disputeManager), appealFee);

        (uint256 appealId, uint256 requestId) = disputeManager.appeal(parentDisputeId, description);

        vm.stopPrank();

        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));

        return (appealId, requestId);
    }

    function _getNewlyAddedJurors(uint256 disputeId) internal view returns (address[] memory) {
        address[] memory disputeJurors = disputeStorage.getDisputeJurors(disputeId);
        address[] memory newlyAdded = new address[](disputeJurors.length);
        uint256 newlyAddedCount = 0;

        for (uint256 i = 0; i < disputeJurors.length; i++) {
            address currentJurorAddress = disputeJurors[i];
            // console.log("Current juror address in _getNewlyAdded Jurors: ", currentJurorAddress);
            TypesLib.Candidate memory isDisputeCandidate =
                disputeStorage.getDisputeCandidate(disputeId, currentJurorAddress);
            TypesLib.Vote memory currentVote = disputeStorage.getDisputeVote(disputeId, currentJurorAddress);
            if (!isDisputeCandidate.missed && currentVote.support == address(0)) {
                // console.log("Missed jurror: ", currentJurorAddress);
                newlyAdded[newlyAddedCount] = currentJurorAddress;
                newlyAddedCount++;
            }
        }

        assembly {
            mstore(newlyAdded, newlyAddedCount)
        }

        return newlyAdded;
    }

    function _assertVote(
        TypesLib.Vote memory vote,
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
        TypesLib.Candidate memory candidate,
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

    function _assertNotReAdded(address[] memory newlyAdded, address[] memory jurors) internal pure {
        for (uint256 i = 0; i < jurors.length; i++) {
            address currentJurorAddress = jurors[i];
            for (uint256 j = 0; j < newlyAdded.length; j++) {
                address currentNewlyAdded = newlyAdded[j];
                assertNotEq(currentJurorAddress, currentNewlyAdded);
            }
        }
    }

    function _finishDispute() internal returns (bool, bytes memory) {
        // Finish dispute by upkeep;
        bytes memory empty = "";
        (bool upkeepNeeded, bytes memory performData) = jurorManager.checkUpkeep(empty);
        // (uint256[] memory toExtend, uint256[] memory toFinish) = abi.decode(performData, (uint256[], uint256[]));

        vm.startPrank(disputeManager.owner());
        jurorManager.performUpkeep(performData);
        vm.stopPrank();

        return (upkeepNeeded, performData);
    }

    function testJurorManagerDeployed() external view {
        assert(address(jurorManager) != address(0));
    }

    function testOpenDispute() external {
        // //  You should not be able to open dispute if you haven't create a deal in the first place

        // Register some jurors
        address juror1 = _registerJuror(makeAddr("juror1"), 2000e18);
        address juror2 = _registerJuror(makeAddr("juror2"), 4000e18);
        address juror3 = _registerJuror(makeAddr("juror3"), 6000e18);
        address juror4 = _registerJuror(makeAddr("juror4"), 8000e18);
        address juror5 = _registerJuror(makeAddr("juror5"), 1500e18);
        address juror6 = _registerJuror(makeAddr("juror6"), 9000e18);

        // Send LinkToken to the JurorManager contract
        // LinkToken linkToken = LinkToken(networkConfig.linkAddress);
        // vm.prank(address(helperConfig));
        // linkToken.mint(address(jurorManager), 10000e18);

        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 100e18;
        string memory description = "Test open dispute";
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);

        // Then you should be able to open a dispute;
        (uint256 disputeId, uint256 requestId) = _openDispute(sender, dealId, description);

        //  //     // Then call fulfillRandomWords
        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));

        // Let's use juror 1
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;
        // uint256[] memory jurorHistory = disputeStorage.getJurorDisputeHistory(juror1);
        // assertEq(jurorHistory[0], disputeId);
        // assertEq(disputeStorage.ongoingDisputeCount(juror1), 1);
        address[] memory disputeJurors = disputeStorage.getDisputeJurors(disputeId);
        assertEq(disputeJurors.length, newbieNeeded + expNeeded);

        // TypesLib.Candidate memory candidate = disputeStorage.getDisputeCandidate(disputeId, juror1);
        // assertEq(candidate.stakeAmount, 2000e18);

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
        assert(disputeStorage.allJurorAddresses(0) == juror1);
        assert(disputeStorage.activeJurorAddresses(0) == juror1);
        assert(disputeStorage.jurorAddressIndex(juror1) == 0);

        TypesLib.Juror memory juror = disputeStorage.getJuror(juror1);

        assert(juror.stakeAmount == stakeAmount);
        assert(juror.reputation == 0);
        assert(juror.jurorAddress == juror1);
        assert(juror.missedVotesCount == 0);
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
        string memory description = "Test can vote";
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        address juror5 = _registerJuror(makeAddr("juror5"), 1500e18);
        address juror6 = _registerJuror(makeAddr("juror6"), 9000e18);

        // Then you should be able to open a dispute;
        (disputeId,) = _openDispute(sender, dealId, description);

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = disputeStorage.getDisputeJurors(disputeId);

        // Get the dispute itself;
        TypesLib.Dispute memory dispute = disputeStorage.getDispute(disputeId);

        // Assert candidates;
        TypesLib.Candidate memory candidate0 = disputeStorage.getDisputeCandidate(disputeId, disputeJurors[0]);
        TypesLib.Candidate memory candidate1 = disputeStorage.getDisputeCandidate(disputeId, disputeJurors[1]);
        TypesLib.Candidate memory candidate2 = disputeStorage.getDisputeCandidate(disputeId, disputeJurors[2]);

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
        TypesLib.Vote memory vote0 = _vote(disputeId, disputeJurors[0], dispute.sender);
        TypesLib.Vote memory vote1 = _vote(disputeId, disputeJurors[1], dispute.receiver);
        TypesLib.Vote memory vote2 = _vote(disputeId, disputeJurors[2], dispute.sender);

        // Revert if disputeJurors0 tries to vote again;
        vm.startPrank(disputeJurors[0]);
        vm.expectRevert(abi.encodeWithSelector(JurorManager.JurorManager__AlreadyVoted.selector));
        jurorManager.vote(disputeId, dispute.receiver);
        vm.stopPrank();

        // Revert if someone that is not chosen tries to vote;
        vm.startPrank(juror5);
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
        string memory description = "Test can finish dispute";
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 9000e18);

        // Then you should be able to open a dispute;
        (uint256 disputeId, uint256 requestId) = _openDispute(sender, dealId, description);

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = disputeStorage.getDisputeJurors(disputeId);

        // Get the dispute itself;
        TypesLib.Dispute memory dispute = disputeStorage.getDispute(disputeId);

        // Juros can vote;
        address disputeJuror1 = disputeJurors[0];
        address disputeJuror2 = disputeJurors[1];
        address disputeJuror3 = disputeJurors[2];

        _vote(disputeId, disputeJuror1, dispute.sender);
        _vote(disputeId, disputeJuror2, dispute.receiver);
        _vote(disputeId, disputeJuror3, dispute.sender);

        TypesLib.Juror memory juror1Before = disputeStorage.getJuror(disputeJuror1);
        TypesLib.Juror memory juror2Before = disputeStorage.getJuror(disputeJuror2);
        TypesLib.Juror memory juror3Before = disputeStorage.getJuror(disputeJuror3);

        // Fast forward time;
        vm.warp(block.timestamp + 49 hours);

        // Finish dispute by upkeep;
        bytes memory empty = "";
        (bool upkeepNeeded, bytes memory performData) = jurorManager.checkUpkeep(empty);
        (uint256[] memory toExtend, uint256[] memory toFinish) = abi.decode(performData, (uint256[], uint256[]));

        assertEq(upkeepNeeded, true);
        assertEq(toFinish.length, 1);

        vm.startPrank(disputeManager.owner());
        jurorManager.performUpkeep(performData);
        vm.stopPrank();

        // // Check states;

        // Make sure that the Dispute itself has been updated to reflect the new winnner.
        assertEq(disputeStorage.getDispute(disputeId).winner, dispute.sender);

        // Check to see that the reputation and stake amount of the people voted winner have updated accordingly.
        TypesLib.Juror memory juror1After = disputeStorage.getJuror(disputeJuror1);
        TypesLib.Juror memory juror2After = disputeStorage.getJuror(disputeJuror2);
        TypesLib.Juror memory juror3After = disputeStorage.getJuror(disputeJuror3);

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
        disputeManager.releaseFundsToWinner(disputeId);
        vm.stopPrank();

        // Fast forward to after appeal period;
        vm.warp(block.timestamp + disputeStorage.appealDuration());

        // Loser cannot call releaseFundsToWinner
        vm.startPrank(dispute.receiver);
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__OnlyWinner.selector));
        disputeManager.releaseFundsToWinner(disputeId);
        vm.stopPrank();

        // Check the balance of the winner before funds is released;
        IERC20Mock token = IERC20Mock(deal.tokenAddress);
        uint256 winnerTokenBalanceBefore = token.balanceOf(dispute.sender);

        // Release funds to winner
        vm.startPrank(dispute.sender);
        disputeManager.releaseFundsToWinner(disputeId);
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
        string memory description = "Test can appeal";
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 9000e18);

        // Then you should be able to open a dispute;
        (uint256 disputeId,) = _openDispute(sender, dealId, description);

        // Select Jurors
        uint256 expNeeded = 2;
        uint256 newbieNeeded = 1;

        // Get all the jurors assigned to disputeId;
        address[] memory disputeJurors = disputeStorage.getDisputeJurors(disputeId);

        // Get the dispute itself;
        TypesLib.Dispute memory dispute = disputeStorage.getDispute(disputeId);

        // Juros can vote;
        address disputeJuror1 = disputeJurors[0];
        address disputeJuror2 = disputeJurors[1];
        address disputeJuror3 = disputeJurors[2];

        _vote(disputeId, disputeJuror1, dispute.sender);
        _vote(disputeId, disputeJuror2, dispute.receiver);
        _vote(disputeId, disputeJuror3, dispute.sender);

        // Fast forward time;
        vm.warp(block.timestamp + 49 hours);

        // Finish dispute by upkeep;
        bytes memory empty = "";
        (bool upkeepNeeded, bytes memory performData) = jurorManager.checkUpkeep(empty);
        (uint256[] memory toExtend, uint256[] memory toFinish) = abi.decode(performData, (uint256[], uint256[]));

        assertEq(upkeepNeeded, true);
        assertEq(toFinish.length, 1);

        vm.startPrank(disputeManager.owner());
        jurorManager.performUpkeep(performData);
        vm.stopPrank();

        // Fast forward to after appeal period;
        vm.warp(block.timestamp);

        // Loser appealing
        uint256 firstRound = 2;
        uint256 appealFee = feeController.calculateAppealFee(deal.tokenAddress, deal.amount, firstRound);

        IERC20Mock token = IERC20Mock(deal.tokenAddress);

        // Mint to the loser
        vm.prank(address(helperConfig));
        token.mint(dispute.receiver, appealFee);

        // Then the loser seeks for appeal;
        vm.prank(dispute.receiver);
        token.approve(address(disputeManager), appealFee);

        // Loser should not be able to make appeal because appeal period has passed;
        string memory appealReason = "I am appealing because...";
        // (uint256 appealId, uint256 requestId) = disputeManager.appeal(disputeId, description);
        (uint256 appealId, uint256 requestId) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 2, appealReason);

        // // Check the states after appeal;
        // Check whether the dispute id has been linked to the new appeal
        uint256[] memory disputeAppeals = disputeStorage.getDisputeAppeals(disputeId);
        assertEq(disputeAppeals[0], appealId);

        // Check whether the count has ben updated;
        uint256 disputeAppealCount = disputeStorage.appealCounts(disputeId);
        assertEq(disputeAppealCount, 1);
    }

    function testCanAppealTwice() external {
        // Appeal two times and then finish dispute
        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        string memory description = "I am appealing because...";

        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 11000e18);
        _registerJuror(makeAddr("juror7"), 1000e18);
        _registerJuror(makeAddr("juror8"), 4300e18);
        _registerJuror(makeAddr("juror9"), 14000e18);
        _registerJuror(makeAddr("juror10"), 765000e18);

        // Then you should be able to open a dispute;
        (uint256 disputeId,) = _openDispute(sender, dealId, description);

        // Select jurors
        address[] memory jurors1 = disputeStorage.getDisputeJurors(disputeId);
        TypesLib.Timer memory disputeTimer = disputeStorage.getDisputeTimer(disputeId);
        address[] memory votes1 = new address[](3);
        votes1[0] = sender;
        votes1[1] = receiver;
        votes1[2] = sender;
        _voteFlow(disputeId, jurors1, votes1);

        // Print everything about disputeTimer;
        console.log("Dispute timer start: ", disputeTimer.startTime);
        console.log("Dispute standard voting duration: ", disputeTimer.standardVotingDuration);
        console.log("Dispute extend duration: ", disputeTimer.extendDuration);

        // vm.warp(block.timestamp + 47 hours);

        (bool upkeepNeeded1, bytes memory performData1) = _finishDispute();
        assertEq(upkeepNeeded1, true);
        (uint256[] memory toExtend1, uint256[] memory toFinish1) = abi.decode(performData1, (uint256[], uint256[]));
        assertEq(toFinish1.length, 1);

        // First appeal
        (uint256 appealId1, uint256 requestId) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 2, description);

        address[] memory jurors2 = disputeStorage.getDisputeJurors(appealId1);
        address[] memory votes2 = new address[](5);
        votes2[0] = sender;
        votes2[1] = receiver;
        votes2[2] = sender;
        votes2[3] = sender;
        votes2[4] = sender;
        _voteFlow(appealId1, jurors2, votes2);

        //  vm.warp(block.timestamp + 49 hours);

        (bool upkeepNeeded2, bytes memory performData2) = _finishDispute();
        assertEq(upkeepNeeded2, true);
        (uint256[] memory toExtend2, uint256[] memory toFinish2) = abi.decode(performData2, (uint256[], uint256[]));
        assertEq(toFinish2.length, 1);

        // Fast forward to after appeal period;
        // vm.warp(block.timestamp + jurorManager.appealDuration());

        // Second appeal
        (uint256 appealId2,) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 3, description);

        address[] memory jurors3 = disputeStorage.getDisputeJurors(appealId2);
        address[] memory votes3 = new address[](5);
        votes3[0] = receiver;
        votes3[1] = sender;
        votes3[2] = receiver;
        votes3[3] = receiver;
        votes3[4] = receiver;
        _voteFlow(appealId2, jurors3, votes3);

        (bool upkeepNeeded3, bytes memory performData3) = _finishDispute();
        assertEq(upkeepNeeded3, true);
        (uint256[] memory toExtend3, uint256[] memory toFinish3) = abi.decode(performData3, (uint256[], uint256[]));
        assertEq(toFinish3.length, 1);

        // Third appeal should revert
        vm.prank(address(helperConfig));
        IERC20Mock(daiTokenAddress).mint(sender, 7000e18);

        vm.startPrank(sender);
        IERC20Mock(daiTokenAddress).approve(address(disputeManager), 60000e18);
        vm.expectRevert(abi.encodeWithSelector(DisputeManager.DisputeManager__MaxAppealExceeded.selector));
        disputeManager.appeal(disputeId, description);
        vm.stopPrank();

        // Winner claims funds
        vm.warp(block.timestamp + disputeStorage.appealDuration());

        TypesLib.Dispute memory finalDispute = disputeStorage.getDispute(appealId2);
        uint256 balBefore = IERC20Mock(daiTokenAddress).balanceOf(finalDispute.receiver);

        vm.startPrank(finalDispute.receiver);
        disputeManager.releaseFundsToWinner(appealId2);
        vm.stopPrank();

        uint256 balAfter = IERC20Mock(daiTokenAddress).balanceOf(finalDispute.receiver);
        assertEq(balAfter, balBefore + deal.amount);
    }

    function testCanPenalizeIfVoteMissed() external {
        // Here, we create a deal, open dispute, jurors vote on the dispute, then create appeal twice. After creating appwal twice, then some jurors will not vote. Now check whether the jurors that did not vote will be appropriately penalize. Also check if the states would be updated to missed.

        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        string memory description = "abcd";
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 11000e18);
        _registerJuror(makeAddr("juror7"), 1000e18);
        _registerJuror(makeAddr("juror8"), 4300e18);
        _registerJuror(makeAddr("juror9"), 14000e18);
        _registerJuror(makeAddr("juror10"), 725000e18);
        _registerJuror(makeAddr("juror11"), 125000e18);
        _registerJuror(makeAddr("juror12"), 55000e18);
        _registerJuror(makeAddr("juror13"), 656500e18);
        // Then you should be able to open a dispute;
        (uint256 disputeId,) = _openDispute(sender, dealId, description);

        // Select jurors
        address[] memory jurors1 = disputeStorage.getDisputeJurors(disputeId);
        address[] memory votes1 = new address[](3);
        votes1[0] = sender;
        votes1[1] = receiver;
        votes1[2] = sender;
        _voteFlow(disputeId, jurors1, votes1);

        // vm.warp(block.timestamp + jurorManager.appealDuration());

        (bool upkeepNeeded1, bytes memory performData1) = _finishDispute();
        assertEq(upkeepNeeded1, true);
        (uint256[] memory toExtend1, uint256[] memory toFinish1) = abi.decode(performData1, (uint256[], uint256[]));

        console.log("toExtend1: ", toExtend1.length);
        console.log("toFinish1: ", toFinish1.length);
        assertEq(toFinish1.length, 1);

        // First appeal
        (uint256 appealId1,) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 2, description);

        address[] memory jurors2 = disputeStorage.getDisputeJurors(appealId1);
        address[] memory votes2 = new address[](5);
        votes2[0] = sender;
        votes2[1] = receiver;
        votes2[2] = sender;
        votes2[3] = sender;
        votes2[4] = sender;
        _voteFlow(appealId1, jurors2, votes2);

        // Fast forward to after appeal period;
        // vm.warp(block.timestamp + jurorManager.appealDuration());

        (bool upkeepNeeded2, bytes memory performData2) = _finishDispute();
        assertEq(upkeepNeeded2, true);
        (uint256[] memory toExtend2, uint256[] memory toFinish2) = abi.decode(performData2, (uint256[], uint256[]));
        assertEq(toFinish2.length, 1);

        console.log("toExtend2: ", toExtend2.length);
        console.log("toFinish2: ", toFinish2.length);

        // Second appeal
        (uint256 appealId2,) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 3, description);

        address[] memory jurors3 = disputeStorage.getDisputeJurors(appealId2);
        address[] memory votes3 = new address[](3);
        votes3[0] = sender;
        votes3[1] = sender;
        votes3[2] = sender;

        // At this point, we have to add jurors after 48 hours have elapsed. Add 2 more jurors.
        for (uint256 i = 0; i < votes3.length; i++) {
            _vote(appealId2, jurors3[i], votes3[i]);
        }

        // At this point, jurors starting from index 3 to 6 did not vote. So, we add new jurors;
        TypesLib.Timer memory appealTimer2 = disputeStorage.getDisputeTimer(appealId2);
        vm.warp(block.timestamp + appealTimer2.startTime + disputeStorage.votingPeriod() + 1 hours);

        // Let's extend the time with upkeep
        // Finish dispute by upkeep;
        bytes memory empty = "";
        (bool upkeepNeeded, bytes memory performData) = jurorManager.checkUpkeep(empty);
        (uint256[] memory toExtend, uint256[] memory toFinish) = abi.decode(performData, (uint256[], uint256[]));

        console.log("To extend: ", toExtend.length);
        console.log("To finish: ", toFinish.length);

        assertEq(toExtend.length, 1);

        vm.startPrank(disputeManager.owner());
        jurorManager.performUpkeep(performData);
        vm.stopPrank();

        // Vote round 2;
        address[] memory votesNextRound = new address[](3);
        votesNextRound[0] = receiver;
        votesNextRound[1] = receiver;
        votesNextRound[2] = sender;

        // At this point, we have to add jurors after 48 hours have elapsed. Add 2 more jurors.
        for (uint256 i = 0; i < votesNextRound.length; i++) {
            uint256 jurorIndex = i + 3;
            _vote(appealId2, jurors3[jurorIndex], votesNextRound[i]);
        }

        // Now 6 jurors have voted out of 9 jurors;
        vm.warp(block.timestamp + disputeStorage.extendingDuration() + 5 seconds);

        // Then we finish dispute
        _finishDispute();

        // Winner claims funds
        // vm.warp(block.timestamp + disputeStorage.appealDuration());

        TypesLib.Dispute memory finalDispute = disputeStorage.getDispute(appealId2);
        address newWinner = finalDispute.winner;

        assertEq(newWinner, sender);

        uint256 balBefore = IERC20Mock(daiTokenAddress).balanceOf(finalDispute.winner);

        vm.startPrank(finalDispute.winner);
        disputeManager.releaseFundsToWinner(appealId2);
        vm.stopPrank();

        uint256 balAfter = IERC20Mock(daiTokenAddress).balanceOf(finalDispute.winner);
        assertEq(balAfter, balBefore + deal.amount);
    }

    function testAdminCanParticipateInDispute() external {
        // Create a deal;
        address daiTokenAddress = networkConfig.daiTokenAddress;
        uint256 dealAmount = 1000e18;
        string memory description = "abcd";
        uint256 dealId = _createERC20Deal(sender, receiver, daiTokenAddress, dealAmount, description);
        TypesLib.Deal memory deal = bloomEscrow.getDeal(dealId);

        // Register some jurors
        _registerJuror(makeAddr("juror1"), 2000e18);
        _registerJuror(makeAddr("juror2"), 4000e18);
        _registerJuror(makeAddr("juror3"), 6000e18);
        _registerJuror(makeAddr("juror4"), 8000e18);
        _registerJuror(makeAddr("juror5"), 1500e18);
        _registerJuror(makeAddr("juror6"), 11000e18);
        _registerJuror(makeAddr("juror7"), 1000e18);
        _registerJuror(makeAddr("juror8"), 4300e18);
        _registerJuror(makeAddr("juror9"), 14000e18);
        _registerJuror(makeAddr("juror10"), 725000e18);
        _registerJuror(makeAddr("juror11"), 125000e18);
        _registerJuror(makeAddr("juror12"), 55000e18);
        _registerJuror(makeAddr("juror13"), 656500e18);

        // Then you should be able to open a dispute;
        (uint256 disputeId,) = _openDispute(sender, dealId, description);
            console.log("disputeId: ", disputeId);


        address[] memory jurors1 = disputeStorage.getDisputeJurors(disputeId);
        address[] memory votes1 = new address[](3);
        votes1[0] = sender;
        votes1[1] = receiver;
        votes1[2] = sender;
        _voteFlow(disputeId, jurors1, votes1);

        (bool upkeepNeeded1, bytes memory performData1) = _finishDispute();
        assertEq(upkeepNeeded1, true);
        (uint256[] memory toExtend1, uint256[] memory toFinish1) = abi.decode(performData1, (uint256[], uint256[]));

        // vm.warp(block.timestamp + jurorManager.appealDuration());

        // First appeal
        (uint256 appealId1,) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 2, description);
            console.log("AppealId1: ", appealId1);


        address[] memory jurors2 = disputeStorage.getDisputeJurors(appealId1);
        address[] memory votes2 = new address[](5);
        votes2[0] = sender;
        votes2[1] = receiver;
        votes2[2] = sender;
        votes2[3] = sender;
        votes2[4] = sender;
        _voteFlow(appealId1, jurors2, votes2);

        (bool upkeepNeeded2, bytes memory performData2) = _finishDispute();
        assertEq(upkeepNeeded2, true);
        (uint256[] memory toExtend2, uint256[] memory toFinish2) = abi.decode(performData2, (uint256[], uint256[]));
        assertEq(toFinish2.length, 1);

        // Second appeal
        (uint256 appealId2,) =
            _appealFlow(disputeId, receiver, IERC20Mock(daiTokenAddress), deal.amount, 3, description);
            console.log("AppealID2: ", appealId2);

        address[] memory jurors3 = disputeStorage.getDisputeJurors(appealId2);
        address[] memory votes3 = new address[](8);
        votes3[0] = sender;
        votes3[1] = sender;
        votes3[2] = sender;
        votes3[3] = sender;
        votes3[4] = receiver;
        votes3[5] = receiver;
        votes3[6] = receiver;
        votes3[7] = receiver;
        _voteFlow(appealId2, jurors3, votes3);

        // Since it is tie, we have to call the tiebreaker to break it.

        vm.startPrank(sender);
        uint256 requestId = jurorManager.breakTie(appealId2);
        vm.stopPrank();

        VRFV2Wrapper wrapper = helperConfig.getVRFV2Wrapper();
        VRFCoordinatorV2Mock vrfCoordinator = helperConfig.getVRFCoordinator();
        vm.prank(address(helperConfig));
        vrfCoordinator.fulfillRandomWords(requestId, address(wrapper));

        // We have to check whether the tie breaker has been added;
        assertNotEq(disputeStorage.tieBreakerJuror(appealId2), address(0));
    
        address tieBreaker = disputeStorage.tieBreakerJuror(appealId2);
        address[] memory tieBreakerArray = new address[](1);
        tieBreakerArray[0] = tieBreaker;
        _assertNotReAdded(tieBreakerArray, jurors3);

        // The breaker votes
        _vote(appealId2, tieBreaker, receiver);



        // Get dispute share before finish dispute;
        uint256 disputeShareBalanceBefore = disputeStorage.jurorTokenPayments(tieBreaker, daiTokenAddress);

        // Let's fastforward the time;
        vm.warp(block.timestamp + disputeStorage.tieBreakingDuration() + 5 seconds);


        // We then finish the vote.
        _finishDispute();

        uint256 disputeShareBalanceAfter = disputeStorage.jurorTokenPayments(tieBreaker, daiTokenAddress);
        console.log("Dispute share balance after: ", disputeShareBalanceAfter);
        assertGt(disputeShareBalanceAfter, disputeShareBalanceBefore);

        // Winner claims funds
        vm.warp(block.timestamp + disputeStorage.appealDuration());

        TypesLib.Dispute memory finalDispute = disputeStorage.getDispute(appealId2);
        address newWinner = finalDispute.winner;

        assertEq(newWinner, receiver);

        uint256 balBefore = IERC20Mock(daiTokenAddress).balanceOf(finalDispute.receiver);

        vm.startPrank(finalDispute.receiver);
        disputeManager.releaseFundsToWinner(appealId2);
        vm.stopPrank();

        uint256 balAfter = IERC20Mock(daiTokenAddress).balanceOf(finalDispute.receiver);
        assertEq(balAfter, balBefore + deal.amount);

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
}
