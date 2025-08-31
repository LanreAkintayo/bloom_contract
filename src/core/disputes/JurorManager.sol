// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {VRFV2WrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {DisputeManager} from "./DisputeManger.sol";

contract JurorManager is VRFV2WrapperConsumerBase, ConfirmedOwner, DisputeManager {
    using SafeERC20 for IERC20;

     // For randomness;
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => Candidate[]) private experiencedPoolTemporary;
    mapping(uint256 => Candidate[]) private newbiePoolTemporary;
    mapping(uint256 => uint256) private experienceNeededByDispute;
    mapping(uint256 => uint256) private newbieNeededByDispute;
    mapping(uint256 => uint256) private requestIdToDispute;
   

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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event JurorRegistered(address indexed juror, uint256 stakeAmount);
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);
    event MaxStakeAmountUpdated(uint256 newMaxStakeAmount);
    event MoreStaked(address juror, uint256 additionalStaked);
    event JurorsSelected(uint256 indexed disputeId, Candidate[] indexed selected);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _bloomTokenAddress, address _linkAddress, address _wrapperAddress, address _escrowAddress, address _feeControllerAddress)
        ConfirmedOwner(msg.sender)
        VRFV2WrapperConsumerBase(_linkAddress, _wrapperAddress)
        DisputeManager(_escrowAddress, _feeControllerAddress)
    {
       
        bloomToken = IERC20(_bloomTokenAddress);
        linkAddress = _linkAddress;
        wrapperAddress = _wrapperAddress;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    function registerJuror(uint256 stakeAmount) external {
        if (stakeAmount < minStakeAmount || stakeAmount > maxStakeAmount) {
            revert JurorManager__InvalidStakeAmount();
        }

        if (jurors[msg.sender].stakeAmount > 0) {
            revert JurorManager__AlreadyRegistered();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // // Register juror
        Juror memory juror;
        juror.jurorAddress = msg.sender;
        juror.stakeAmount = stakeAmount;
        juror.reputation = 0;

        jurors[msg.sender] = juror;

        // @complete Add to the array of all jurors

        emit JurorRegistered(msg.sender, stakeAmount);
    }

    function stakeMore(uint256 additionalStake) external {
        if (additionalStake == 0) {
            revert JurorManager__ZeroAmount();
        }

        Juror storage juror = jurors[msg.sender];

        if (juror.jurorAddress == address(0)) {
            revert JurorManager__NotRegistered();
        }

        uint256 newStakeAmount = juror.stakeAmount + additionalStake;

        if (newStakeAmount > maxStakeAmount) {
            revert JurorManager__InvalidStakeAmount();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), additionalStake);

        // Update juror stake
        juror.stakeAmount = newStakeAmount;

        emit MoreStaked(msg.sender, additionalStake);
    }

    function computeScore(
        uint256 stakeAmount,
        uint256 reputation,
        uint256 _maxStake,
        uint256 maxReputation,
        uint256 alphaFP,
        uint256 betaFP
    ) public view returns (uint256) {
        uint256 score = (alphaFP * stakeAmount / _maxStake) + (betaFP * (reputation + 1) / (maxReputation + 1));
        return score;
    }

    function selectJurors(
        uint256 disputeId,
        uint256 thresholdFP,
        uint256 alphaFP,
        uint256 betaFP,
        uint256 expNeeded,
        uint256 newbieNeeded,
        uint256 experiencedPoolSize
    ) external onlyOwner {
        // Don't select juror for a dispute that already has a juror
        if (disputeJurors[disputeId].length > 0) {
            revert JurorManager__AlreadyAssignedJurors();
        }

        // To verify the experiencedPoolSize with the one computed off-chain
        uint256 countAbove = 0;

        Candidate[] memory experiencedPoolTemp = new Candidate[](allJurors.length);
        Candidate[] memory newbiePoolTemp = new Candidate[](allJurors.length);
        uint256 expIndex = 0;
        uint256 newIndex = 0;

        uint256 maxStake = 1;
        uint256 maxReputation = 1;

        //// find max stake & reputation
        for (uint256 i = 0; i < allJurors.length; i++) {
            Juror memory juror = allJurors[i];

            // Make sure that we can only select a juror that is currently inactive and their stake amount is greater than the minimum stake amount
            if (isJurorActive[juror.jurorAddress] && juror.stakeAmount >= minStakeAmount) {
                if (juror.stakeAmount > maxStake) maxStake = juror.stakeAmount;
                if (juror.reputation > maxReputation) maxReputation = juror.reputation;
            }
        }

        // compute selection scores and assign to pools
        for (uint256 i = 0; i < allJurors.length; i++) {
            Juror memory juror = allJurors[i];

            if (isJurorActive[juror.jurorAddress] && juror.stakeAmount >= minStakeAmount) {
                uint256 score =
                    computeScore(juror.stakeAmount, juror.reputation, maxStake, maxReputation, alphaFP, betaFP);

                if (score >= thresholdFP) {
                    experiencedPoolTemp[expIndex++] =
                        Candidate(disputeId, juror.jurorAddress, juror.stakeAmount, juror.reputation, score);
                    countAbove++;
                } else {
                    newbiePoolTemp[newIndex++] =
                        Candidate(disputeId, juror.jurorAddress, juror.stakeAmount, juror.reputation, score);
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
        uint256 requestId = requestRandomness(callbackGasLimit, requestConfirmations, numWords);
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        requestIdToDispute[requestId] = disputeId;
    }

    // ------------------- VRF CALLBACK -------------------
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        if (s_requests[_requestId].paid <= 0){
            revert JurorManager__RequestNotFound();
        }
        s_requests[_requestId].fulfilled = true;

        uint256 randomness = _randomWords[0];
        uint256 disputeId = requestIdToDispute[_requestId];

        Candidate[] memory experiencedPool = experiencedPoolTemporary[disputeId];
        Candidate[] memory newbiePool = newbiePoolTemporary[disputeId];

        uint256 expNeeded = experienceNeededByDispute[disputeId];
        uint256 newbieNeeded = newbieNeededByDispute[disputeId];
        uint256 total = expNeeded + newbieNeeded;

        Candidate[] memory selected = new Candidate[](total);
        uint256 idx = 0;
        uint256 rand = randomness;

        // pick experienced jurors
        for (uint256 i = 0; i < expNeeded; i++) {
            uint256 pickIdx = rand % experiencedPool.length;
            selected[idx++] = experiencedPool[pickIdx];

            // swap-remove
            experiencedPool[pickIdx] = experiencedPool[experiencedPool.length - 1];
            assembly {
                mstore(experiencedPool, sub(mload(experiencedPool), 1))
            }

            rand = uint256(keccak256(abi.encodePacked(rand, i))) % experiencedPool.length;
        }

        // pick newbie jurors
        for (uint256 i = 0; i < newbieNeeded; i++) {
            uint256 pickIdx = rand % newbiePool.length;
            selected[idx++] = newbiePool[pickIdx];

            // swap-remove
            newbiePool[pickIdx] = newbiePool[newbiePool.length - 1];
            assembly {
                mstore(newbiePool, sub(mload(newbiePool), 1))
            }

            rand = uint256(keccak256(abi.encodePacked(rand, i))) % newbiePool.length;
        }

        // mark jurors active
        for (uint256 i = 0; i < selected.length; i++) {
            isJurorActive[selected[i].jurorAddress] = true;
        }

        disputeJurors[disputeId] = selected;

        emit JurorsSelected(disputeId, selected);
    }

    function vote(uint256 disputeId) external {
        // Make sure that the caller is one of the selected juror for the dispute

        // Then you vote

        // Emit event



    }

    function finishDispute(uint256 dealId) external onlyOwner {
        // Code to finalize the dispute and distribute rewards/penalties
    }

    function _updateReputation(uint256 dealId, address juror, bool wonDispute) internal {
        // Code to update juror reputation based on dispute outcome
    }

    function updateMinStakeAmount(uint256 _minStakeAmount) external onlyOwner {
        if (_minStakeAmount == 0) {
            revert JurorManager__ZeroAmount();
        }
        minStakeAmount = _minStakeAmount;
        emit MinStakeAmountUpdated(_minStakeAmount);
    }

    function updateMaxStakeAmount(uint256 _maxStakeAmount) external onlyOwner {
        if (_maxStakeAmount == 0) {
            revert JurorManager__ZeroAmount();
        }
        maxStakeAmount = _maxStakeAmount;
        emit MaxStakeAmountUpdated(_maxStakeAmount);
    }
}
