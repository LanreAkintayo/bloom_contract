// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";

abstract contract DisputeStorage {
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
        uint256 dealId;
        address initiator;
        address sender;
        address receiver;
        address winner;
    }

    struct Juror {
        address jurorAddress;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 missedVotesCount;
    }

    // Keeps track of the stake amount and reputation at selection
    struct Candidate {
        uint256 disputeId;
        address jurorAddress;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 score;
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
        uint256 endingTime;
        uint256 extendedBy;
    }

    //////////////////////////
    // STATE VARIABLES
    //////////////////////////

    // External contracts
    IBloomEscrow public bloomEscrow;
    IFeeController public feeController;
    IERC20 public bloomToken;

    // Disputes and evidences
    uint256 public disputeId;
    uint256 public constant MAX_PERCENT  = 10_000; // This represents 100%
    mapping(uint256 disputeId => Dispute) public disputes;

    // address can either be the sender or the proposed receiver
    mapping(uint256 dealId => mapping(address => Evidence[])) public dealEvidences;

    // Jurors
    mapping(address jurorAddress => Juror) public jurors;
    Juror[] public allJurors;
    mapping(address jurorAddress => bool) public isJurorActive;
    mapping(address jurorAddress => uint256[] disputeIds) public jurorDisputeHistory;

    // Candidates and voting
    uint256 public lambda = 0.2e18;  // Smoothing factor between 0 and 1 scaled by 1e18
    uint256 public k = 5;  // Step size 
    uint256 public noVoteK = 8; // Step size for not failing to vote
    uint256 public votingPeriod = 48 hours;
    mapping(uint256 disputeId => Candidate[]) public disputeJurors;
    mapping(uint256 disputeId => Timer) public disputeTimer;
    mapping(uint256 disputeId => mapping(address jurorAddress => Vote)) public disputeVotes;
    mapping(uint256 disputeId => Vote[]) public allDisputeVotes;

    // Staking rules
    uint256 public minStakeAmount = 1000e18;
    uint256 public maxStakeAmount = 1_000_000_000e18;
    uint256 public slashPercentage = 1000; // 10% by default
    uint256 public noVoteSlashPercentage = 2000; // 20% by default

    // Chainlink VRF
    uint32 public callbackGasLimit = 500000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;
    address public linkAddress;
    address public wrapperAddress;

    uint256[] public requestIds;
    uint256 public lastRequestId;
}
