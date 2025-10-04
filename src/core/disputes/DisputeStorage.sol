// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBloomEscrow} from "../../interfaces/IBloomEscrow.sol";
import {IFeeController} from "../../interfaces/IFeeController.sol";
import {TypesLib} from "../../library/TypesLib.sol";
import {console} from "forge-std/Test.sol";


contract DisputeStorage {
    //////////////////////////
    // ERRORS
    //////////////////////////

    error DisputeStorage__ZeroAmount();
    error DisputeStorage__NotInStandardVotingPeriod();

    //////////////////////////
    // EVENTS
    //////////////////////////

    event MinStakeAmountUpdated(uint256 minStakeAmount);
    event MaxStakeAmountUpdated(uint256 maxStakeAmount);
    event StandardVotingDurationExtended(uint256 disputeId, uint256 newDuration);

    //////////////////////////
    // EXTERNAL CONTRACTS
    //////////////////////////

    IBloomEscrow public bloomEscrow;
    IFeeController public feeController;
    IERC20 public bloomToken;
    address public wrappedNative;

    //////////////////////////
    // DISPUTES AND EVIDENCES
    //////////////////////////

    uint256 public disputeId;
    uint256 public constant MAX_PERCENT = 10_000; // 100%
    uint256 public constant WAD = 1e18;

    uint256[] public allDisputes;
    mapping(uint256 => bool) public ongoingDisputes;

    mapping(uint256 dealId => uint256 disputeId) public dealToDispute;
    mapping(uint256 disputeId => TypesLib.Dispute) public disputes;
    mapping(uint256 dealId => mapping(address => TypesLib.Evidence[])) public dealEvidences;

    uint256 public maxStake;
    uint256 public maxReputation;
    uint256 public maxScore;
    bool public scoreDirty;

    address public maxStakeJuror;
    address public maxReputationJuror;
    address public maxScoreJuror;

    uint256 maxStakeCap = 10_000_000e18; // → maximum stake we will count
    uint256 stakeScale = 2_000_000e18; // → scaling constant for stake (instead of S)
    uint256 reputationScale = 50; // → scaling constant for reputation (instead of R)

    uint256 stakeWeight = 0.5e18; // → weight of stake in score (percentage, 0–100)
    uint256 reputationWeight = 0.5e18; // → weight of reputation in score (percentage, 0–100)

    //////////////////////////
    // JURORS
    //////////////////////////

    uint256 public lockedPercentage = 7000; // 70%
    uint256 public cooldownDuration = block.chainid == 31337 ? 7 days : 15 minutes;
    uint256 public extendingDuration = block.chainid == 31337 ? 7 days : 15 hours;

    mapping(address jurorAddress => TypesLib.Juror) public jurors;
    address[] public allJurorAddresses;
    address[] public activeJurorAddresses;

    address[] public newbiePool;
    mapping(address jurorAddress => uint256) public newbiePoolIndex;

    address[] public experiencedPool;
    mapping(address jurorAddress => uint256) public experiencedPoolIndex;

    mapping(address jurorAddress => bool) public isJurorActive;
    mapping(address jurorAddress => uint256[] disputeIds) public jurorDisputeHistory;
    mapping(address jurorAddress => uint256) public ongoingDisputeCount;
    mapping(address jurorAddress => uint256 index) public jurorAddressIndex;

    mapping(uint256 disputeId => address) public tieBreakerJuror;
    mapping(address jurorAddress => mapping(address tokenAddress => uint256)) public jurorTokenPayments;
    mapping(address jurorAddress => mapping(address tokenAddress => uint256)) public jurorTokenPaymentsClaimed;
    mapping(uint256 disputeId => mapping(address jurorAddress => TypesLib.PaymentType)) public disputeToJurorPayment;

    mapping(uint256 disputeId => mapping(address tokenAddress => uint256)) public residuePayments;
    mapping(uint256 disputeId => mapping(address tokenAddress => uint256)) public residuePaymentsClaimed;
    mapping(address tokenAddress => uint256) public totalResidue;

    //////////////////////////
    // CANDIDATES & VOTING
    //////////////////////////
    uint256 public thresholdPercent = 6000; // 60% (top 40% will be in the experienced pool)
    uint256 public appealThreshold = 20;
    uint256 public missedVoteThreshold = 20;
    uint256 public ongoingDisputeThreshold = 20;
    uint256 public lambda = 0.2e18; // Smoothing factor scaled by 1e18
    uint256 public k = 5;
    uint256 public noVoteK = 8;
    uint256 public votingPeriod = block.chainid == 31337 ? 48 hours : 2 hours;
    uint256 public tieBreakingDuration = 1 days;

    mapping(uint256 disputeId => address[] jurorAddresses) public disputeJurors;
    mapping(uint256 disputeId => mapping(address jurorAddress => TypesLib.Candidate)) public isDisputeCandidate;
    mapping(uint256 disputeId => TypesLib.Timer) public disputeTimer;
    mapping(uint256 disputeId => mapping(address jurorAddress => TypesLib.Vote)) public disputeVotes;
    mapping(uint256 disputeId => TypesLib.Vote[]) public allDisputeVotes;

    //////////////////////////
    // APPEALS
    //////////////////////////

    mapping(uint256 disputeId => uint256[] appeals) public disputeAppeals;
    mapping(uint256 disputeId => uint256) public appealCounts;
    mapping(uint256 appealId => uint256 disputeId) public appealToDispute;

    uint256 public appealDuration = block.chainid == 31337 ? 24 hours : 10 minutes;

    //////////////////////////
    // STAKING RULES
    //////////////////////////

    uint256 public minStakeAmount = 1000e18;
    uint256 public maxStakeAmount = 1_000_000e18;
    uint256 public slashPercentage = 1000; // 10%
    uint256 public noVoteSlashPercentage = 2000; // 20%
    uint256 public maxSlashPercentage = 5000; // 50%
    uint256 public basePercentage = 1000; // 10%

    //////////////////////////
    // CHAINLINK VRF
    //////////////////////////

    uint32 public callbackGasLimit = 1_800_000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 2;
    address public linkAddress;
    address public wrapperAddress;

    //////////////////////////
    // CONSTRUCTOR
    //////////////////////////
    constructor(address _bloomEscrow, address _feeController, address _bloomTokenAddress, address _wrappedNative) {
        bloomEscrow = IBloomEscrow(_bloomEscrow);
        feeController = IFeeController(_feeController);
        bloomToken = IERC20(_bloomTokenAddress);
        wrappedNative = _wrappedNative;
    }

    //////////////////////////
    // VIEW FUNCTIONS
    //////////////////////////

    function getJurorComposition(uint256 _disputeId, uint256 _appealId) external view returns(uint256 expNeeded, uint256 newbieNeeded) {
        uint256[] memory appeals = disputeAppeals[_disputeId];

        if (appeals.length == 0){
            console.log("Juror Composition: Original Dispute");
            expNeeded = 3;
            newbieNeeded = 2;
        } else if (appeals[0] == _appealId) {
            console.log("Juror Composition: First appeal");
            expNeeded = 4;
            newbieNeeded = 3;
        } else if (appeals[1] == _appealId){
            console.log("Juror Composition: Second appeal");
            expNeeded = 5;
            newbieNeeded = 4;
        }
    }

    function getExperiencedPool() external view returns (address[] memory) {
        return experiencedPool;
    }

    function getNewbiePool() external view returns (address[] memory) {
        return newbiePool;
    }

    function getDispute(uint256 _disputeId) external view returns (TypesLib.Dispute memory) {
        return disputes[_disputeId];
    }

    function getDisputeJurors(uint256 _disputeId) external view returns (address[] memory) {
        return disputeJurors[_disputeId];
    }

    function getDisputeAppeals(uint256 _disputeId) external view returns (uint256[] memory) {
        return disputeAppeals[_disputeId];
    }

    function getDisputeTimer(uint256 _disputeId) external view returns (TypesLib.Timer memory) {
        return disputeTimer[_disputeId];
    }

    function getAllDisputeVotes(uint256 _disputeId) external view returns (TypesLib.Vote[] memory) {
        return allDisputeVotes[_disputeId];
    }

    function getDisputeCandidate(uint256 _disputeId, address _jurorAddress)
        external
        view
        returns (TypesLib.Candidate memory)
    {
        return isDisputeCandidate[_disputeId][_jurorAddress];
    }

    function getDisputeVote(uint256 _disputeId, address _jurorAddress) external view returns (TypesLib.Vote memory) {
        return disputeVotes[_disputeId][_jurorAddress];
    }

    function getJuror(address _jurorAddress) external view returns (TypesLib.Juror memory) {
        return jurors[_jurorAddress];
    }

    function getJurorTokenPayment(address _jurorAddress, address _tokenAddress) external view returns (uint256) {
        return jurorTokenPayments[_jurorAddress][_tokenAddress];
    }

    function getOngoingDisputeCount(address _jurorAddress) external view returns (uint256) {
        return ongoingDisputeCount[_jurorAddress];
    }

    function getResiduePayment(uint256 _disputeId, address _tokenAddress) external view returns (uint256) {
        return residuePayments[_disputeId][_tokenAddress];
    }

    function getDealEvidence(uint256 _dealId, address _ownerAddress)
        external
        view
        returns (TypesLib.Evidence[] memory)
    {
        return dealEvidences[_dealId][_ownerAddress];
    }

    function isInActiveJurorAddresses(address _jurorAddress) external view returns (bool) {
        return activeJurorAddresses[jurorAddressIndex[_jurorAddress]] == _jurorAddress;
    }

    function getBloomEscrow() external view returns (IBloomEscrow) {
        return bloomEscrow;
    }

    function getFeeController() external view returns (IFeeController) {
        return feeController;
    }

    function getBloomToken() external view returns (IERC20) {
        return bloomToken;
    }

    function getActiveJurorAddresses() external view returns (address[] memory) {
        return activeJurorAddresses;
    }

    function getAllJurorAddresses() external view returns (address[] memory) {
        return allJurorAddresses;
    }

    function getJurorDisputeHistory(address _jurorAddress) external view returns (uint256[] memory) {
        return jurorDisputeHistory[_jurorAddress];
    }

    function getAllDisputes() external view returns (uint256[] memory) {
        return allDisputes;
    }


    //////////////////////////
    // STATE-CHANGING FUNCTIONS
    //////////////////////////

    function incrementDisputeId() external returns (uint256) {
        disputeId += 1;
        return disputeId;
    }

    function setDisputes(uint256 _disputeId, TypesLib.Dispute memory _dispute) external {
        disputes[_disputeId] = _dispute;
    }

    function setDealToDispute(uint256 _dealId, uint256 _disputeId) external {
        dealToDispute[_dealId] = _disputeId;
    }

    function setTieBreakJuror(uint256 _disputeId, address _jurorAddress) external{
        tieBreakerJuror[_disputeId] = _jurorAddress;
    }

    function updateDisputeWinner(uint256 _disputeId, address _winner) external {
        disputes[_disputeId].winner = _winner;
    }

    function updateAllDisputes(uint256 _disputeId) external {
        allDisputes.push(_disputeId);
    }

    function updateDisputeStatus(uint256 _disputeId, bool _status) external {
        ongoingDisputes[_disputeId] = _status;
    }

    function updateDisputeJurors(uint256 _disputeId, address[] memory _jurors) external {
        disputeJurors[_disputeId] = _jurors;
    }

    function incrementAppealCount(uint256 _disputeId) external returns (uint256) {
        appealCounts[_disputeId] += 1;
        return appealCounts[_disputeId];
    }

    function updateDisputeTimer(uint256 _disputeId, TypesLib.Timer memory _timer) external {
        disputeTimer[_disputeId] = _timer;
    }

    function pushIntoDisputeAppeals(uint256 _disputeId, uint256 _appealId) external {
        disputeAppeals[_disputeId].push(_appealId);
    }

    function setAppealToDispute(uint256 _appealId, uint256 _disputeId) external {
        appealToDispute[_appealId] = _disputeId;
    }

    function updateDisputeCandidate(uint256 _disputeId, address _jurorAddress, TypesLib.Candidate memory _candidate)
        external
    {
        isDisputeCandidate[_disputeId][_jurorAddress] = _candidate;
    }

    function pushIntoAllDisputeVotes(uint256 _disputeId, TypesLib.Vote memory _vote) external {
        allDisputeVotes[_disputeId].push(_vote);
    }

    function updateDisputeVote(uint256 _disputeId, address _jurorAddress, TypesLib.Vote memory _vote) external {
        disputeVotes[_disputeId][_jurorAddress] = _vote;
    }

    function incrementOngoingDisputeCount(address _jurorAddress) external {
        ongoingDisputeCount[_jurorAddress] += 1;
    }

    function decrementOngoingDisputeCount(address _jurorAddress) external {
        ongoingDisputeCount[_jurorAddress] -= 1;
    }

    function updateOngoingDisputeCount(address _jurorAddress, uint256 _count) external {
        ongoingDisputeCount[_jurorAddress] = _count;
    }

    function updateJuror(address _jurorAddress, TypesLib.Juror memory _juror) external {
        jurors[_jurorAddress] = _juror;
    }

    function updateJurorStakeAmount(address _jurorAddress, uint256 _stakeAmount) external {
        jurors[_jurorAddress].stakeAmount = _stakeAmount;
    }

    function balanceMaxScore(address _jurorAddress) external {
        if (jurors[_jurorAddress].score > maxScore) {
            maxScore = jurors[_jurorAddress].score;
            maxScoreJuror = _jurorAddress;
        } else if (_jurorAddress == maxScoreJuror && jurors[_jurorAddress].score < maxScore) {
            _rebalanceMaxScore();
        }
    }

    function updateJurorReputation(address _jurorAddress, uint256 _reputation) external {
        jurors[_jurorAddress].reputation = _reputation;
    }

    function updateJurorScore(address _jurorAddress) external {
        TypesLib.Juror memory juror = jurors[_jurorAddress];
        uint256 newScore = computeScore(juror.stakeAmount, juror.reputation);
        jurors[_jurorAddress].score = newScore;
    }

    function updateCandidateMissedStatus(uint256 _disputeId, address _jurorAddress, bool _status) external {
        isDisputeCandidate[_disputeId][_jurorAddress].missed = _status;
    }

    function updateJurorMissedVotesCount(address _jurorAddress, uint256 _missedVotesCount) external {
        jurors[_jurorAddress].missedVotesCount = _missedVotesCount;
    }

    function updateJurorTokenPayments(address _jurorAddress, address _tokenAddress, uint256 _amount) external {
        jurorTokenPayments[_jurorAddress][_tokenAddress] = _amount;
    }

    function updateJurorTokenPaymentsClaimed(address _jurorAddress, address _tokenAddress, uint256 _amount) external {
        jurorTokenPaymentsClaimed[_jurorAddress][_tokenAddress] += _amount;

    }

    function updateDisputeToJurorPayment(
        uint256 _disputeId,
        address _jurorAddress,
        TypesLib.PaymentType calldata _paymentType
    ) external {
        disputeToJurorPayment[_disputeId][_jurorAddress] = _paymentType;
    }

    function updateResiduePayments(uint256 _disputeId, address _tokenAddress, uint256 _amount) external {
        residuePayments[_disputeId][_tokenAddress] = _amount;
    }

    function updateTotalResidue(address _tokenAddress, uint256 _amount) external {
        totalResidue[_tokenAddress] = _amount;
    }

    function updateMaxStake(uint256 _amount) external {
        if (_amount > maxStake) {
            maxStake = _amount;
        }
    }

    function updateMaxReputation(uint256 _reputation) external {
        if (_reputation > maxReputation) {
            maxReputation = _reputation;
        }
    }

    function computeScore(uint256 _stakeAmount, uint256 _reputation) public view returns (uint256) {
        uint256 stakeUsed = _stakeAmount > maxStakeCap ? maxStakeCap : _stakeAmount;
        uint256 stakeScore = (stakeUsed * WAD) / (stakeUsed + stakeScale);
        uint256 reputationScore = (_reputation * WAD) / (_reputation + reputationScale);

        uint256 score = (stakeWeight * stakeScore) / WAD + (reputationWeight * reputationScore) / WAD;
        return score;
    }

    function pushIntoDealEvidences(uint256 _dealId, address _ownerAddress, TypesLib.Evidence memory _evidence)
        external
    {
        dealEvidences[_dealId][_ownerAddress].push(_evidence);
    }

    function removeEvidence(uint256 _evidenceIndex, uint256 _dealId, address _ownerAddress) external {
        dealEvidences[_dealId][_ownerAddress][_evidenceIndex].removed = true;
    }

    function popFromActiveJurorAddresses(address _jurorAddress) external {
        uint256 lastJurorIndex = activeJurorAddresses.length - 1;
        uint256 currentJurorIndex = jurorAddressIndex[_jurorAddress];

        if (currentJurorIndex != lastJurorIndex) {
            address lastJurorAddress = activeJurorAddresses[lastJurorIndex];
            activeJurorAddresses[currentJurorIndex] = lastJurorAddress;
            jurorAddressIndex[lastJurorAddress] = currentJurorIndex;
        }

        activeJurorAddresses.pop();
        delete jurorAddressIndex[_jurorAddress];
    }

    function pushToActiveJurorAddresses(address _jurorAddress) external {
        jurorAddressIndex[_jurorAddress] = activeJurorAddresses.length;
        activeJurorAddresses.push(_jurorAddress);
    }

    function pushIntoAllJurorAddresses(address _jurorAddress) external {
        allJurorAddresses.push(_jurorAddress);
    }

    function pushIntoJurorDisputeHistory(address _jurorAddress, uint256 _disputeId) external {
        jurorDisputeHistory[_jurorAddress].push(_disputeId);
    }

    function extendVotingDuration(uint256 _disputeId, uint256 _duration) external {
        disputeTimer[_disputeId].extendDuration = _duration;
    }

    function pushIntoDisputeJurors(address _jurorAddress, uint256 _disputeId) external {
        disputeJurors[_disputeId].push(_jurorAddress);
    }

    function updateJurorLastWithdrawn(address _jurorAddress, uint256 _lastWithdrawn) external {
        jurors[_jurorAddress].lastWithdrawn = _lastWithdrawn;
    }

    //////////////////////////
    // PARAMETERS UPDATE
    //////////////////////////

    function updateMinStakeAmount(uint256 _minStakeAmount) external {
        if (_minStakeAmount == 0) revert DisputeStorage__ZeroAmount();
        minStakeAmount = _minStakeAmount;
        emit MinStakeAmountUpdated(_minStakeAmount);
    }

    function updateMaxStakeAmount(uint256 _maxStakeAmount) external {
        if (_maxStakeAmount == 0) revert DisputeStorage__ZeroAmount();
        maxStakeAmount = _maxStakeAmount;
        emit MaxStakeAmountUpdated(_maxStakeAmount);
    }

    function extendStandardVotingDuration(uint256 _disputeId, uint256 _extendDuration) external {
        TypesLib.Timer storage timer = disputeTimer[_disputeId];

        if (block.timestamp > timer.startTime + timer.standardVotingDuration) {
            revert DisputeStorage__NotInStandardVotingPeriod();
        }

        timer.standardVotingDuration = _extendDuration;
        emit StandardVotingDurationExtended(_disputeId, _extendDuration);
    }

    function _rebalanceMaxScore() internal {
        uint256 maxScoreTemp;
        address maxScoreJurorTemp;

        for (uint256 i = 0; i < allJurorAddresses.length; i++) {
            address jurorAddress = allJurorAddresses[i];
            TypesLib.Juror memory juror = jurors[jurorAddress];

            if (juror.score > maxScoreTemp) {
                maxScoreTemp = juror.score;
                maxScoreJurorTemp = jurorAddress;
            }
        }
        maxScore = maxScoreTemp;
        maxScoreJuror = maxScoreJurorTemp;
    }

    //////////////////////////
    // TESTING/CONFIG
    //////////////////////////

    function changeCallbackGasLimit(uint32 _callbackGasLimit) external {
        callbackGasLimit = _callbackGasLimit;
    }

    function changeVotingPeriod(uint256 _votingPeriod) external {
        votingPeriod = _votingPeriod;
    }
    function changeTieBreakingDuration(uint256 _tieBreakingDuration) external {
        tieBreakingDuration = _tieBreakingDuration;
    }

    function changeExtendDuration(uint256 _extendDuration) external {
        extendingDuration = _extendDuration;
    }
}
