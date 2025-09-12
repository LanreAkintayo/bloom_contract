// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";
import {TypesLib} from "../../library/TypesLib.sol";

contract DisputeStorage {
   

    //////////////////////////
    // STATE VARIABLES
    //////////////////////////

    // External contracts
    IBloomEscrow public bloomEscrow;
    IFeeController public feeController;
    IERC20 public bloomToken;
    address public wrappedNative;

    // Disputes and evidences
    uint256 public disputeId;
    uint256 public constant MAX_PERCENT = 10_000; // This represents 100%
    mapping(uint256 dealId => uint256 disputeId) public dealToDispute;
    mapping(uint256 disputeId => TypesLib.Dispute) public disputes;

    // address can either be the sender or the proposed receiver
    mapping(uint256 dealId => mapping(address => TypesLib.Evidence[])) public dealEvidences;

    // Jurors
    uint256 public lockedPercentage = 7000; // 70% of the staked amount will be locked
    uint256 public cooldownDuration = block.chainid == 31337 ? 15 minutes : 7 days;
    mapping(address jurorAddress => TypesLib.Juror) public jurors;
    address[] public allJurorAddresses;
    mapping(address jurorAddress => bool) public isJurorActive;
    mapping(address jurorAddress => uint256[] disputeIds) public jurorDisputeHistory;
    mapping(address jurorAddress => uint256) public ongoingDisputeCount;
    address[] public activeJurorAddresses;
    mapping(address jurorAddrres => uint256 index) public jurorAddressIndex;
    mapping(address jurorAddress => mapping(address tokenAddress => uint256)) public jurorTokenPayments;
    mapping(address jurorAddress => mapping(address tokenAddress => uint256)) public jurorTokenPaymentsClaimed;
    mapping(uint256 disputeId => mapping(address jurorAddress => TypesLib.PaymentType)) public disputeToJurorPayment;

    mapping(uint256 disputeId => mapping(address tokenAddress => uint256)) public residuePayments;
    mapping(uint256 disputeId => mapping(address tokenAddress => uint256)) public residuePaymentsClaimed;
    mapping(address tokenAddress => uint256) public totalResidue;

    // Candidates and voting
    uint256 public appealThreshold = 3;
    uint256 public missedVoteThreshold = 3;
    uint256 public ongoingDisputeThreshold = 3;
    uint256 public lambda = 0.2e18; // Smoothing factor between 0 and 1 scaled by 1e18
    uint256 public k = 5; // Step size
    uint256 public noVoteK = 8; // Step size for not failing to vote
    uint256 public votingPeriod = block.chainid == 31337 ? 15 minutes : 48 hours;
    mapping(uint256 disputeId => address[] jurorAddresses) public disputeJurors;
    mapping(uint256 disputeId => mapping(address jurorAddress => TypesLib.Candidate)) public isDisputeCandidate;
    mapping(uint256 disputeId => TypesLib.Timer) public disputeTimer;
    mapping(uint256 disputeId => mapping(address jurorAddress => TypesLib.Vote)) public disputeVotes;
    mapping(uint256 disputeId => TypesLib.Vote[]) public allDisputeVotes;

    // Appeals
    mapping(uint256 disputeId => uint256[] appeals) public disputeAppeals;
    mapping(uint256 disputeId => uint256) public appealCounts;
    uint256 public appealDuration = block.chainid == 31337 ? 10 minutes : 24 hours;
    mapping(uint256 appealId => uint256 disputeId) public appealToDispute;

    // Staking rules
    uint256 public minStakeAmount = 1000e18;
    uint256 public maxStakeAmount = 1_000_000_000e18;
    uint256 public slashPercentage = 1000; // 10% by default
    uint256 public noVoteSlashPercentage = 2000; // 20% by default
    uint256 public maxSlashPercentage = 5000; // 50% at most.
    uint256 public basePercentage = 1000; // 10% of the base fee to be distributed to all participants.

    // Chainlink VRF
    uint32 public callbackGasLimit = 1_600_000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;
    address public linkAddress;
    address public wrapperAddress;

    uint256[] public requestIds;
    uint256 public lastRequestId;


    function incrementDisputeId() external returns (uint256) {
        disputeId += 1;
        return disputeId;
    }

    function setDisputes(uint256 _disputeId, TypesLib.Dispute memory _dispute) external {
        disputes[_disputeId] = _dispute;
    }

    function getDispute(uint256 _disputeId) external view returns (TypesLib.Dispute memory) {
        return disputes[_disputeId];
    }

    function setDealToDispute(uint256 _dealId, uint256 _disputeId) external {
        dealToDispute[_dealId] = _disputeId;
    }

    function updateDisputeWinner(uint256 _disputeId, address _winner) external {
        disputes[_disputeId].winner = _winner;
    }

    function getDisputeJurors(uint256 _disputeId) external view returns (address[] memory) {
        return disputeJurors[_disputeId];
    }
    function getDisputeAppeals(uint256 _disputeId) external view returns (uint256[] memory) {
        return disputeAppeals[_disputeId];
    }

    function incrementAppealCount(uint256 _disputeId) external returns(uint256) {
        appealCounts[_disputeId] += 1;
        return appealCounts[_disputeId];
    }

    function getDisputeTimer(uint256 _disputeId) external view returns (TypesLib.Timer memory) {
        return disputeTimer[_disputeId];
    }

    function pushIntoDisputeAppeals(uint256 _disputeId, uint256 _appealId) external {
        disputeAppeals[_disputeId].push(_appealId);
    }

    function setAppealToDispute(uint256 _appealId, uint256 _disputeId) external {
        appealToDispute[_appealId] = _disputeId;
    }

    function getAllDisputeVotes(uint256 _disputeId) external view returns (TypesLib.Vote[] memory) {
        return allDisputeVotes[_disputeId];
    }

    function getDisputeCandidate(uint256 _disputeId, address _jurorAddress) external view returns (TypesLib.Candidate memory) {
        return isDisputeCandidate[_disputeId][_jurorAddress];
    }
}
