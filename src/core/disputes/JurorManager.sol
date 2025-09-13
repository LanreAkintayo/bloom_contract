// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VRFV2WrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import {DisputeStorage} from "./DisputeStorage.sol";

import {DisputeManager} from "./DisputeManager.sol";
import {TypesLib} from "../../library/TypesLib.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

// import {console} from "forge-std/Test.sol";

contract JurorManager is VRFV2WrapperConsumerBase, ConfirmedOwner {
    using SafeERC20 for IERC20;

    DisputeStorage public ds;

    IERC20 public bloomToken;
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint256 public constant MAX_PERCENT = 10_000; // This represents 100%

    // For randomness;
    mapping(uint256 => TypesLib.RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => address[]) private experiencedPoolTemporary;
    mapping(uint256 => address[]) private newbiePoolTemporary;
    mapping(uint256 => uint256) private experienceNeededByDispute;
    mapping(uint256 => uint256) private newbieNeededByDispute;
    mapping(uint256 => uint256) private requestIdToDispute;
    mapping(uint256 => mapping(address => uint256)) private selectionScoresTemp;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error JurorManager__ZeroAddress();
    error JurorManager__ZeroAmount();
    error JurorManager__InvalidStakeAmount();
    error JurorManager__AlreadyRegistered();
    error JurorManager__NotRegistered();
    error JurorManager__AlreadyAssignedJurors();
    error JurorManager__ThresholdMismatched();
    error JurorManager__RequestNotFound();
    error JurorManager__NotEligible();
    error JurorManager__AlreadyVoted();
    error JurorManager__MaxVoteExceeded();
    error JurorManager__NotFinished();
    error JurorManager__DisputeNotEnded();
    error JurorManager__NotInVotingPeriod();
    error JurorManager__VotingPeriodExpired();
    error JurorManager__NotInStandardVotingPeriod();
    error JurorManager__MaxAppealExceeded();
    error JurorManager__AlreadyWinner();
    error JurorManager__MustVote();
    error JurorManager__NotEnoughStakeToWithdraw();
    error JurorManager__WithdrawalCooldownNotOver();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event JurorRegistered(address indexed juror, uint256 stakeAmount);
    event MinStakeAmountUpdated(uint256 indexed newMinStakeAmount);
    event MaxStakeAmountUpdated(uint256 indexed newMaxStakeAmount);
    event MoreStaked(address indexed juror, uint256 indexed additionalStaked);
    event JurorsSelected(uint256 indexed disputeId, address[] indexed selected);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);
    event Voted(uint256 indexed disputeId, address indexed jurorAddress, address indexed support);
    event AdminParticipatedInDispute(uint256 indexed _disputeId, address indexed support);
    event JurorAdded(uint256 indexed _disputeId, address[] indexed newJurors);
    event StandardVotingDurationExtended(uint256 indexed _disputeId, uint256 indexed _extendDuration);
    event StakeWithdrawn(address indexed jurorAddress, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _storageAddress, address _bloomTokenAddress, address _linkAddress, address _wrapperAddress)
        VRFV2WrapperConsumerBase(_linkAddress, _wrapperAddress)
        ConfirmedOwner(msg.sender)
    {   
        ds = DisputeStorage(_storageAddress);
        bloomToken = ds.getBloomToken();
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    function registerJuror(uint256 stakeAmount) external {
        TypesLib.Juror memory juror = ds.getJuror(msg.sender);
        if (stakeAmount < ds.minStakeAmount() || stakeAmount > ds.maxStakeAmount()) {
            revert JurorManager__InvalidStakeAmount();
        }

        if (juror.stakeAmount > 0) {
            revert JurorManager__AlreadyRegistered();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // // Register juror
        TypesLib.Juror memory newJuror;
        newJuror.jurorAddress = msg.sender;
        newJuror.stakeAmount = stakeAmount;
        newJuror.reputation = 0;
        newJuror.missedVotesCount = 0;

        ds.updateJuror(msg.sender, newJuror);
        // jurors[msg.sender] = juror;

        // Add addres to the list of all the juror addresses
        ds.pushIntoAllJurorAddresses(msg.sender);
        // allJurorAddresses.push(msg.sender);

        // Add a new fresh juror to the activejurorAddresses
        ds.pushToActiveJurorAddresses(msg.sender);
        // _pushToActiveJurorAddresses(msg.sender);

        emit JurorRegistered(msg.sender, stakeAmount);
    }

    function stakeMore(uint256 additionalStake) external {
        if (additionalStake == 0) {
            revert JurorManager__ZeroAmount();
        }

        TypesLib.Juror memory juror = ds.getJuror(msg.sender); // jurors[msg.sender];

        if (juror.jurorAddress == address(0)) {
            revert JurorManager__NotRegistered();
        }

        uint256 newStakeAmount = juror.stakeAmount + additionalStake;

        if (newStakeAmount > ds.maxStakeAmount()) {
            revert JurorManager__InvalidStakeAmount();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), additionalStake);

        // Update juror stake
        ds.updateJurorStakeAmount(msg.sender, newStakeAmount);
        // juror.stakeAmount = newStakeAmount;

        emit MoreStaked(msg.sender, additionalStake);
    }

    function computeScore(
        uint256 stakeAmount,
        uint256 reputation,
        uint256 _maxStake,
        uint256 maxReputation,
        uint256 alphaFP,
        uint256 betaFP
    ) public pure returns (uint256) {
        uint256 score = (alphaFP * stakeAmount / _maxStake) + (betaFP * (reputation + 1) / (maxReputation + 1));
        return score;
    }

    /**
     * @notice Selects jurors for a given dispute based on experience and fairness constraints.
     * @param disputeId The ID of the dispute for which jurors are being selected.
     * @param thresholdFP The minimum threshold in fixedPointScale (1e18) to be counted as an experienced juror.
     * @param alphaFP The weight factor applied to increase the intensity of stake during selection.
     * @param betaFP The weight factor applied to increase the intensity of reputation during selection.
     * @param expNeeded The number of experienced jurors required for this dispute.
     * @param newbieNeeded The number of newbie jurors required for this dispute.
     * @param experiencedPoolSize The total number of experienced jurors available in the pool based on offchain calculations
     */
    function selectJurors(
        uint256 disputeId,
        uint256 thresholdFP,
        uint256 alphaFP,
        uint256 betaFP,
        uint256 expNeeded,
        uint256 newbieNeeded,
        uint256 experiencedPoolSize
    ) external onlyOwner returns (uint256) {
        // Don't select juror for a dispute that already has a juror
        address[] memory disputeJurors = ds.getDisputeJurors(disputeId);
        address[] memory activeJurorAddresses = ds.getActiveJurorAddresses();

        if (disputeJurors.length > 0) {
            revert JurorManager__AlreadyAssignedJurors();
        }

        // To verify the experiencedPoolSize with the one computed off-chain
        uint256 countAbove = 0;

        // Create a temporary array to store the selected jurors (experienced and newbies)
        address[] memory experiencedPoolTemp = new address[](activeJurorAddresses.length);
        address[] memory newbiePoolTemp = new address[](activeJurorAddresses.length);

        // Create an index for the arrays (experienced and newbies)
        uint256 expIndex = 0;
        uint256 newIndex = 0;

        uint256 maxStake = 0;
        uint256 maxReputation = 0;

        //// find max stake & reputation
        for (uint256 i = 0; i < activeJurorAddresses.length; i++) {
            address currentJurorAddress = activeJurorAddresses[i];
            TypesLib.Juror memory juror = ds.getJuror(currentJurorAddress); // jurors[currentJurorAddress];

            // Make sure that we can only select a juror that is currently inactive and their stake amount is greater than the minimum stake amount
            if (juror.stakeAmount >= ds.minStakeAmount()) {
                if (juror.stakeAmount > maxStake) maxStake = juror.stakeAmount;
                if (juror.reputation > maxReputation) maxReputation = juror.reputation;
            }
        }

        // compute selection scores and assign to pools
        for (uint256 i = 0; i < activeJurorAddresses.length; i++) {
            TypesLib.Juror memory juror = ds.getJuror(activeJurorAddresses[i]); // jurors[activeJurorAddresses[i]];

            if (juror.stakeAmount >= ds.minStakeAmount()) {
                uint256 score =
                    computeScore(juror.stakeAmount, juror.reputation, maxStake, maxReputation, alphaFP, betaFP);

                if (score >= thresholdFP) {
                    experiencedPoolTemp[expIndex++] = juror.jurorAddress;
                    selectionScoresTemp[disputeId][juror.jurorAddress] = score;

                    countAbove++;
                } else {
                    newbiePoolTemp[newIndex++] = juror.jurorAddress;
                    selectionScoresTemp[disputeId][juror.jurorAddress] = score;
                }
            }
        }

        if (countAbove != experiencedPoolSize) {
            revert JurorManager__ThresholdMismatched();
        }

        // resize arrays
        assembly {
            mstore(experiencedPoolTemp, expIndex)
        }
        assembly {
            mstore(newbiePoolTemp, newIndex)
        }

        // store temp pools for VRF callback
        experiencedPoolTemporary[disputeId] = experiencedPoolTemp;
        newbiePoolTemporary[disputeId] = newbiePoolTemp;
        experienceNeededByDispute[disputeId] = expNeeded;
        newbieNeededByDispute[disputeId] = newbieNeeded;

        // request randomness from Chainlink VRF
        uint256 requestId = requestRandomness(ds.callbackGasLimit(), ds.requestConfirmations(), ds.numWords());

        s_requests[requestId] = TypesLib.RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(ds.callbackGasLimit()),
            randomWords: new uint256[](0),
            fulfilled: false
        });

        // console.log("Request ID: ", requestId);
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, ds.numWords());
        requestIdToDispute[requestId] = disputeId;

        return requestId;
    }

    // ------------------- VRF CALLBACK -------------------
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        // console.log("Request ID in the contract:", _requestId);
        // console.log("Random words:", _randomWords[0]);

        if (s_requests[_requestId].paid <= 0) {
            revert JurorManager__RequestNotFound();
        }
        s_requests[_requestId].fulfilled = true;

        uint256 randomness = _randomWords[0];
        uint256 disputeId = requestIdToDispute[_requestId];

        address[] memory experiencedPool = experiencedPoolTemporary[disputeId];
        address[] memory newbiePool = newbiePoolTemporary[disputeId];

        // I want to print out the content of experienced pool and newbie pool for testing sake
        // console.log("Experienced Pool Length: ", experiencedPool.length);
        // for (uint256 i = 0; i < experiencedPool.length; i++) {
        //     // console.log("experienced pool address: ", experiencedPool[i], "with selection score : ", selectionScoresTemp[disputeId][experiencedPool[i]]);
        // }

        // // console.log("Newbie Pool Length: ", newbiePool.length);
        // for (uint256 i = 0; i < newbiePool.length; i++) {
        //     // console.log("newbie pool address: ", newbiePool[i], "with selection score : ", selectionScoresTemp[disputeId][newbiePool[i]]);
        // }

        uint256 expNeeded = experienceNeededByDispute[disputeId];
        uint256 newbieNeeded = newbieNeededByDispute[disputeId];
        uint256 total = expNeeded + newbieNeeded;

        address[] memory selected = new address[](total);
        uint256 idx = 0;
        uint256 rand = randomness;

        // pick experienced jurors
        for (uint256 i = 0; i < expNeeded; i++) {
            uint256 pickIdx = rand % experiencedPool.length;
            address selectedJurorAddress = experiencedPool[pickIdx];
            TypesLib.Juror memory correspondingJuror = ds.getJuror(selectedJurorAddress); // jurors[selectedJurorAddress];
            selected[idx++] = selectedJurorAddress;

            // Update the candidate mapping;
            TypesLib.Candidate memory correspondingCandidate = TypesLib.Candidate(
                disputeId,
                selectedJurorAddress,
                correspondingJuror.stakeAmount,
                correspondingJuror.reputation,
                selectionScoresTemp[disputeId][selectedJurorAddress],
                false
            );

            ds.updateDisputeCandidate(disputeId, selectedJurorAddress, correspondingCandidate);
            // isDisputeCandidate[disputeId][selectedJurorAddress] =

            // Track all the disputes per juror
            ds.pushIntoJurorDisputeHistory(selectedJurorAddress, disputeId);
            // jurorDisputeHistory[selectedJurorAddress].push(disputeId);

            // swap-remove
            experiencedPool[pickIdx] = experiencedPool[experiencedPool.length - 1];
            assembly {
                mstore(experiencedPool, sub(mload(experiencedPool), 1))
            }

            rand = uint256(keccak256(abi.encodePacked(rand, i)));
            // console.log("Random: ", rand);
        }

        // pick newbie jurors
        for (uint256 i = 0; i < newbieNeeded; i++) {
            uint256 pickIdx = rand % newbiePool.length;
            address selectedJurorAddress = newbiePool[pickIdx];
            TypesLib.Juror memory correspondingJuror = ds.getJuror(selectedJurorAddress); // jurors[selectedJurorAddress];
            selected[idx++] = selectedJurorAddress;

            // Update the candidate mapping;
            TypesLib.Candidate memory correspondingCandidate = TypesLib.Candidate(
                disputeId,
                selectedJurorAddress,
                correspondingJuror.stakeAmount,
                correspondingJuror.reputation,
                selectionScoresTemp[disputeId][selectedJurorAddress],
                false
            );

            ds.updateDisputeCandidate(disputeId, selectedJurorAddress, correspondingCandidate);
            // isDisputeCandidate[disputeId][selectedJurorAddress] =

            // Track all the disputes per juror
            ds.pushIntoJurorDisputeHistory(selectedJurorAddress, disputeId);

            // isDisputeCandidate[disputeId][selectedJurorAddress] = Candidate(
            //     disputeId,
            //     selectedJurorAddress,
            //     correspondingJuror.stakeAmount,
            //     correspondingJuror.reputation,
            //     selectionScoresTemp[disputeId][selectedJurorAddress],
            //     false
            // );

            // Track all the disputes per juror
            // jurorDisputeHistory[selectedJurorAddress].push(disputeId);

            // swap-remove
            newbiePool[pickIdx] = newbiePool[newbiePool.length - 1];
            assembly {
                mstore(newbiePool, sub(mload(newbiePool), 1))
            }

            rand = uint256(keccak256(abi.encodePacked(rand, i)));
        }

        // mark jurors active
        for (uint256 i = 0; i < selected.length; i++) {
            address selectedAddress = selected[i];
            uint256 ongoingDisputeCount = ds.ongoingDisputeCount(selectedAddress);
            ds.updateOngoingDisputeCount(selectedAddress, ongoingDisputeCount + 1);

            // ongoingDisputeCounFt[selectedAddress] += 1;

            bool isPresent = ds.isInActiveJurorAddresses(selectedAddress);
            if (ongoingDisputeCount > ds.ongoingDisputeThreshold() && isPresent) {
                ds.popFromActiveJurorAddresses(selectedAddress);
            }
        }

        // As per they are active here, let me remove from them from the available jurors.

        // I want to print the list of all the selected jurors;
        // for (uint256 i = 0; i < selected.length; i++) {
        //     // console.log("Selected jurors: ", selected[i], "with selection score : ", selectionScoresTemp[disputeId][selected[i]]);
        // }

        // console.log("In fulfill randomw words, block.timestamp is ", block.timestamp);
        // console.log("In fulfill randomw words, startTime is ", _startTime);

        ds.updateDisputeJurors(disputeId, selected);
        // disputeJurors[disputeId] = selected;

        ds.updateDisputeTimer(disputeId, TypesLib.Timer(disputeId, block.timestamp, ds.votingPeriod(), 0));
        // disputeTimer[disputeId] = Timer(disputeId, block.timestamp, votingPeriod, 0);

        emit JurorsSelected(disputeId, selected);
    }

    function vote(uint256 disputeId, address support) external {
        // Make sure that the caller is one of the selected juror for the dispute
        bool isEligible = checkVoteEligibility(disputeId, msg.sender);
        TypesLib.Dispute memory dispute = ds.getDispute(disputeId);
        uint256 correspondingDealId = dispute.dealId;
        TypesLib.Timer memory timer = ds.getDisputeTimer(disputeId); // disputeTimer[disputeId];
        TypesLib.Vote memory jurorVote = ds.getDisputeVote(disputeId, msg.sender); // disputeVotes[disputeId][msg.sender];
        TypesLib.Vote[] memory allDisputeVotes = ds.getAllDisputeVotes(disputeId);
        address[] memory disputeJurors = ds.getDisputeJurors(disputeId);
        if (support == address(0)) {
            revert JurorManager__MustVote();
        }
        if (block.timestamp > timer.startTime + timer.standardVotingDuration + timer.extendDuration) {
            revert JurorManager__VotingPeriodExpired();
        }

        if (!isEligible) {
            revert JurorManager__NotEligible();
        }

        // Make sure voter has not voted before;
        if (jurorVote.jurorAddress != address(0)) {
            revert JurorManager__AlreadyVoted();
        }

        // Make sure that the number of votes is equal to the number of candidates selected to vote;
        if (allDisputeVotes.length + 1 > disputeJurors.length) {
            revert JurorManager__MaxVoteExceeded();
        }
        // Then you vote
        TypesLib.Vote memory newVote = TypesLib.Vote(msg.sender, disputeId, correspondingDealId, support);

        ds.updateDisputeVote(disputeId, msg.sender, newVote);
        // disputeVotes[disputeId][msg.sender] = newVote;

        ds.pushIntoAllDisputeVotes(disputeId, newVote);
        // allDisputeVotes[disputeId].push(newVote);

        // Emit event
        emit Voted(disputeId, msg.sender, support);
    }

    function checkVoteEligibility(uint256 disputeId, address voter) public view returns (bool isEligible) {
        // You are eligible if you are one of the assigned jurors
        address[] memory disputeVoters = ds.getDisputeJurors(disputeId); // disputeJurors[disputeId];

        for (uint256 i = 0; i < disputeVoters.length; i++) {
            if (disputeVoters[i] == voter) {
                isEligible = true;
                break;
            }
        }
    }

    function addJuror(uint256 _disputeId, uint256 numJurors, uint256 duration) external onlyOwner {
        // Incase there is a tie breaker, this will help in resolving that.

        // This will be called only after the voting period has elapsed
        TypesLib.Timer memory timer = ds.getDisputeTimer(_disputeId); // disputeTimer[_disputeId];
        if (
            block.timestamp < timer.startTime + timer.standardVotingDuration
                || block.timestamp > timer.startTime + timer.standardVotingDuration + timer.extendDuration
        ) {
            revert JurorManager__NotInVotingPeriod();
        }

        // Mark the novoters as missed.
        address[] memory selectedJurorAddresses = ds.getDisputeJurors(_disputeId); // disputeJurors[_disputeId];
        address[] memory activeJurorAddresses = ds.getActiveJurorAddresses();

        for (uint256 i = 0; i < selectedJurorAddresses.length; i++) {
            address jurorAddress = selectedJurorAddresses[i];
            TypesLib.Vote memory jurorVote = ds.getDisputeVote(_disputeId, jurorAddress); // disputeVotes[_disputeId][jurorAddress];
            TypesLib.Candidate memory isDisputeCandidate = ds.getDisputeCandidate(_disputeId, jurorAddress);
            TypesLib.Juror memory juror = ds.getJuror(jurorAddress);

            if (jurorVote.support == address(0) && !isDisputeCandidate.missed) {
                ds.updateCandidateMissedStatus(_disputeId, jurorAddress, true);
                // isDisputeCandidate[_disputeId][jurorAddress].missed = true;
                ds.updateJurorMissedVotesCount(jurorAddress, juror.missedVotesCount + 1);
                // jurors[jurorAddress].missedVotesCount += 1;

                if (
                    juror.missedVotesCount >= 3
                        && activeJurorAddresses[ds.jurorAddressIndex(jurorAddress)] != address(0)
                ) {
                    ds.popFromActiveJurorAddresses(jurorAddress);
                    // _popFromActiveJurorAddresses(jurorAddress);
                }
            }
        }
        // Get a list of the jurors that are eligble for selection in this stage;
        // You must not 3+ missed, you must be active (meaning that you should not be part of an ongoing dispute, you must not be part of the jurors for that dispute.)
        address[] memory eligibleAddresses = _getEligibleJurorAddresses(_disputeId);
        // console.log("Eligible addresses length is : ", eligibleAddresses.length);

        // Selection will be done in this address of jurors;
        address[] memory newJurors = _pickRandomJurors(eligibleAddresses, numJurors);

        // Add jurors to the candidate list;
        _addJurorsToCandidateList(_disputeId, newJurors);

        // Extend the time

        ds.extendVotingDuration(_disputeId, duration);
        // timer.extendDuration = duration;

        emit JurorAdded(_disputeId, newJurors);
    }

    function _addJurorsToCandidateList(uint256 _disputeId, address[] memory selectedJurorAddresses) internal {
        for (uint256 i = 0; i < selectedJurorAddresses.length; i++) {
            address jurorAddress = selectedJurorAddresses[i];
            TypesLib.Juror memory juror = ds.getJuror(jurorAddress); // jurors[jurorAddress];

            if (jurorAddress == owner()) {
                ds.updateDisputeCandidate(
                    _disputeId,
                    jurorAddress,
                    TypesLib.Candidate({
                        disputeId: _disputeId,
                        jurorAddress: jurorAddress,
                        stakeAmount: 0,
                        reputation: 0,
                        score: 0,
                        missed: false
                    })
                );
            } else {
                ds.updateDisputeCandidate(
                    _disputeId,
                    jurorAddress,
                    TypesLib.Candidate({
                        disputeId: _disputeId,
                        jurorAddress: juror.jurorAddress,
                        stakeAmount: juror.stakeAmount,
                        reputation: juror.reputation,
                        score: 0,
                        missed: false
                    })
                );
            }
            // Set to active and pop from activeJurorAddresses
            ds.pushIntoDisputeJurors(jurorAddress, _disputeId);
            // disputeJurors[_disputeId].push(jurorAddress);

            ds.popFromActiveJurorAddresses(jurorAddress);
            // _popFromActiveJurorAddresses(jurorAddress);

            ds.updateOngoingDisputeCount(jurorAddress, ds.ongoingDisputeCount(jurorAddress) + 1);
            // ongoingDisputeCount[jurorAddress] += 1;

            // If there are 3+ ongoing disputes, remove from active jurors
            bool isPresent = ds.isInActiveJurorAddresses(jurorAddress);
            if (ds.ongoingDisputeCount(jurorAddress) > ds.ongoingDisputeThreshold() && isPresent) {
                ds.popFromActiveJurorAddresses(jurorAddress);

                // _popFromActiveJurorAddresses(jurorAddress);
            }
        }
    }

    function _pickRandomJurors(address[] memory eligibleAddresses, uint256 numJurors)
        internal
        view
        returns (address[] memory jurors)
    {
        // If no eligible one, just pick the admin
        if (eligibleAddresses.length == 0) {
            jurors = new address[](1);
            jurors[0] = owner();
            return jurors;
        }

        // If fewer eligible than required, return all
        if (eligibleAddresses.length <= numJurors) {
            return eligibleAddresses;
        }

        jurors = new address[](numJurors);

        uint256 poolSize = eligibleAddresses.length;
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, msg.sender)));

        for (uint256 i = 0; i < numJurors; i++) {
            uint256 selectedIndex = randomSeed % poolSize;
            jurors[i] = eligibleAddresses[selectedIndex];

            // Swap with last element in pool
            eligibleAddresses[selectedIndex] = eligibleAddresses[poolSize - 1];

            // Shrink pool
            poolSize--;

            // Update randomness for next pick
            randomSeed = uint256(keccak256(abi.encodePacked(randomSeed, i)));
        }

        return jurors;
    }

    function _getEligibleJurorAddresses(uint256 _disputeId) internal view returns (address[] memory) {
        // For eligibility, you must not have missed to vote for the same dispute, your minimum stake amount must be greather than the minimum stake amount
        address[] memory activeJurorAddresses = ds.getActiveJurorAddresses();
        address[] memory eligibleAddresses = new address[](activeJurorAddresses.length);
        uint256 index;

        for (uint256 i = 0; i < activeJurorAddresses.length; i++) {
            // console.log("activejurorAddress", i, " is ", activeJurorAddresses[i]);
            address jurorAddress = activeJurorAddresses[i];
            TypesLib.Candidate memory isDisputeCandidate = ds.getDisputeCandidate(_disputeId, jurorAddress);
            TypesLib.Juror memory juror = ds.getJuror(jurorAddress);
            bool isAlreadyDisputeJuror = isDisputeCandidate.disputeId == _disputeId;

            // console.log("_disputeId is", _disputeId);
            // console.log(
            //     "isDisputeCAndidate[_disputeId][jurorAddress].disputeId (Already among the jurors)",
            //     jurorAddress,
            //     " is ",
            //     isDisputeCandidate[_disputeId][jurorAddress].disputeId == _disputeId
            // );

            // console.log(
            //     "disputeVotes[_disputeId][jurorAddress].support",
            //     jurorAddress,
            //     " is ",
            //     disputeVotes[_disputeId][jurorAddress].support
            // );

            // console.log("missed vote of ", activeJurorAddresses[i], " is ", missedVote);

            bool hasStake = juror.stakeAmount >= ds.minStakeAmount();

            if (isAlreadyDisputeJuror || !hasStake) {
                // console.log("Jurror ", jurorAddress, " is not eligible");
                continue;
            } else {
                eligibleAddresses[index++] = jurorAddress;
            }
        }

        // console.log("Inside _getEligibleJurorAddresses");

        // Shrink the eligibleAddresses size;
        assembly {
            mstore(eligibleAddresses, index)
        }

        return eligibleAddresses;
    }

    function adminParticipateInDispute(uint256 _disputeId, address _support) external onlyOwner {
        // @complete - don't forget to remove that missed updater here. It's not supposed to be done here
        // To be called by admins
        // Admin is added as candidate. This will be called only after the voting period has elapsed
        TypesLib.Timer memory timer = ds.getDisputeTimer(_disputeId); // disputeTimer[_disputeId];
        if (block.timestamp < timer.startTime + timer.standardVotingDuration + timer.extendDuration) {
            revert JurorManager__DisputeNotEnded();
        }

        // Admin will be added to the candidate list
        // address[] storage selectedJurors = disputeJurors[_disputeId];

        // Mark all the jurors that did not vote as missed;
        // for (uint256 i = 0; i < selectedJurors.length; i++) {
        //     address jurorAddress = selectedJurors[i];
        //     if (disputeVotes[_disputeId][jurorAddress].support == address(0)) {
        //         isDisputeCandidate[_disputeId][jurorAddress].missed = true;
        //     }
        // }

        // Add admin as juror
        ds.pushIntoDisputeJurors(owner(), _disputeId);

        // selectedJurors.push(owner());

        ds.updateDisputeCandidate(
            _disputeId,
            owner(),
            TypesLib.Candidate({
                jurorAddress: owner(),
                stakeAmount: 0,
                disputeId: _disputeId,
                reputation: 0,
                score: 0,
                missed: false
            })
        );

        // isDisputeCandidate[_disputeId][owner()] = Candidate({
        //     jurorAddress: owner(),
        //     stakeAmount: 0,
        //     disputeId: _disputeId,
        //     reputation: 0,
        //     score: 0,
        //     missed: false
        // });

        // Then you vote
        uint256 correspondingDealId = ds.getDispute(_disputeId).dealId; // disputes[_disputeId].dealId;

        TypesLib.Vote memory newVote = TypesLib.Vote(owner(), _disputeId, correspondingDealId, _support);

        ds.updateDisputeVote(_disputeId, msg.sender, newVote);
        // disputeVotes[_disputeId][msg.sender] = newVote;

        ds.pushIntoAllDisputeVotes(_disputeId, newVote);
        // allDisputeVotes[_disputeId].push(newVote);

        // console.log("Length of all dispute votes: ", allDisputeVotes[_disputeId].length);

        emit AdminParticipatedInDispute(_disputeId, _support);
    }

    function withdrawStake(uint256 _stakeAmount) external {
        TypesLib.Juror memory juror = ds.getJuror(msg.sender); // jurors[msg.sender];

        if (block.timestamp < juror.lastWithdrawn + ds.cooldownDuration()) {
            revert JurorManager__WithdrawalCooldownNotOver();
        }

        uint256 totalStakedAmount = juror.stakeAmount;
        uint256 lockedAmount = (ds.lockedPercentage() * totalStakedAmount) / MAX_PERCENT;
        uint256 availableToWithdraw = totalStakedAmount - lockedAmount;

        if (_stakeAmount > availableToWithdraw) {
            revert JurorManager__NotEnoughStakeToWithdraw();
        }

        bloomToken.safeTransfer(msg.sender, _stakeAmount);

        ds.updateJurorStakeAmount(msg.sender, juror.stakeAmount - _stakeAmount);
        // juror.stakeAmount -= _stakeAmount;

        ds.updateJurorLastWithdrawn(msg.sender, block.timestamp);
        // juror.lastWithdrawn = block.timestamp;

        emit StakeWithdrawn(msg.sender, _stakeAmount);
    }
}
