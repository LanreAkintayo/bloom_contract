// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";

contract DisputeStorage {
    //////////////////////////
    // ENUMS
    //////////////////////////

    enum EvidenceType {
        TEXT,
        IMAGE,
        VIDEO,
        AUDIO,
        DOCUMENT
    }

    //////////////////////////
    // STRUCTS
    //////////////////////////

    struct Evidence {
        uint256 dealId;
        address uploader;
        string uri;
        uint256 timestamp;
        EvidenceType evidenceType;
        string description;
        bool removed;
    }

    struct Dispute {
        address initiator;
        address sender;
        address receiver;
        address winner;
        uint256 dealId;
        uint256 disputeFee;
        address feeTokenAddress;
    }

    struct Juror {
        address jurorAddress;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 missedVotesCount;
        uint256 lastWithdrawn;
    }

    // Keeps track of the stake amount and reputation at selection
    struct Candidate {
        uint256 disputeId;
        address jurorAddress;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 score;
        bool missed;
    }

    struct RequestStatus {
        uint256 paid; // Amount paid in LINK
        bool fulfilled; // Whether request was successfully fulfilled
        uint256[] randomWords;
    }

    struct Vote {
        address jurorAddress;
        uint256 disputeId;
        uint256 dealId;
        address support;
    }

    struct Timer {
        uint256 disputeId;
        uint256 startTime;
        uint256 standardVotingDuration;
        uint256 extendDuration;
    }

    struct PaymentType {
        uint256 disputeId;
        address tokenAddress;
        uint256 amount;
    }

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
    mapping(uint256 disputeId => Dispute) public disputes;

    // address can either be the sender or the proposed receiver
    mapping(uint256 dealId => mapping(address => Evidence[])) public dealEvidences;

    // Jurors
    uint256 public lockedPercentage = 7000; // 70% of the staked amount will be locked
    uint256 public cooldownDuration = block.chainid == 31337 ? 15 minutes : 7 days;
    mapping(address jurorAddress => Juror) public jurors;
    address[] public allJurorAddresses;
    mapping(address jurorAddress => bool) public isJurorActive;
    mapping(address jurorAddress => uint256[] disputeIds) public jurorDisputeHistory;
    mapping(address jurorAddress => uint256) public ongoingDisputeCount;
    address[] public activeJurorAddresses;
    mapping(address jurorAddrres => uint256 index) public jurorAddressIndex;
    mapping(address jurorAddress => mapping(address tokenAddress => uint256)) public jurorTokenPayments;
    mapping(address jurorAddress => mapping(address tokenAddress => uint256)) public jurorTokenPaymentsClaimed;
    mapping(uint256 disputeId => mapping(address jurorAddress => PaymentType)) public disputeToJurorPayment;

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
    mapping(uint256 disputeId => mapping(address jurorAddress => Candidate)) public isDisputeCandidate;
    mapping(uint256 disputeId => Timer) public disputeTimer;
    mapping(uint256 disputeId => mapping(address jurorAddress => Vote)) public disputeVotes;
    mapping(uint256 disputeId => Vote[]) public allDisputeVotes;

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
}
