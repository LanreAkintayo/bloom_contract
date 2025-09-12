// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DisputeStorage} from "./DisputeStorage.sol"; // reuse struct Juror

library JurorSelector {
    struct Pools {
        address[] experiencedPoolTemp;
        address[] newbiePoolTemp;
        uint256 countAbove;
        uint256 maxStake;
        uint256 maxReputation;
    }

    function buildPools(
        address[] memory activeJurorAddresses,
        mapping(address => DisputeStorage.Juror) storage jurors,
        uint256 minStakeAmount,
        uint256 thresholdFP,
        uint256 alphaFP,
        uint256 betaFP
    ) internal view returns (Pools memory pools) {
        uint256 maxStake;
        uint256 maxReputation;

        // first loop to find max stake & reputation
        for (uint256 i = 0; i < activeJurorAddresses.length; i++) {
            DisputeStorage.Juror storage juror = jurors[activeJurorAddresses[i]];
            if (juror.stakeAmount >= minStakeAmount) {
                if (juror.stakeAmount > maxStake) maxStake = juror.stakeAmount;
                if (juror.reputation > maxReputation) maxReputation = juror.reputation;
            }
        }

        address[] memory expTemp = new address[](activeJurorAddresses.length);
        address[] memory newTemp = new address[](activeJurorAddresses.length);

        uint256 expIndex;
        uint256 newIndex;
        uint256 countAbove;

        // second loop to assign to pools
        for (uint256 i = 0; i < activeJurorAddresses.length; i++) {
            DisputeStorage.Juror storage juror = jurors[activeJurorAddresses[i]];

            if (juror.stakeAmount >= minStakeAmount) {
                uint256 score = computeScore(
                    juror.stakeAmount,
                    juror.reputation,
                    maxStake,
                    maxReputation,
                    alphaFP,
                    betaFP
                );

                if (score >= thresholdFP) {
                    expTemp[expIndex++] = juror.jurorAddress;
                    countAbove++;
                } else {
                    newTemp[newIndex++] = juror.jurorAddress;
                }
            }
        }

        assembly { mstore(expTemp, expIndex) }
        assembly { mstore(newTemp, newIndex) }

        pools = Pools({
            experiencedPoolTemp: expTemp,
            newbiePoolTemp: newTemp,
            countAbove: countAbove,
            maxStake: maxStake,
            maxReputation: maxReputation
        });
    }

    function computeScore(
        uint256 stake,
        uint256 reputation,
        uint256 maxStake,
        uint256 maxReputation,
        uint256 alphaFP,
        uint256 betaFP
    ) internal pure returns (uint256) {
        uint256 stakeFP = (stake * 1e18) / (maxStake == 0 ? 1 : maxStake);
        uint256 reputationFP = (reputation * 1e18) / (maxReputation == 0 ? 1 : maxReputation);
        return (stakeFP * alphaFP) / 1e18 + (reputationFP * betaFP) / 1e18;
    }
}
