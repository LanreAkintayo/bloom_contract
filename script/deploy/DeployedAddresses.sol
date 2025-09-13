// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title DeployedAddresses
/// @notice Returns deployed contract addresses per network with last-deployed helper
library DeployedAddresses {

    // ---------------- BLOOM ----------------
    function getBloom(uint256 chainId, uint256 index) internal pure returns (address) {
        // Sepolia
        if (chainId == 11155111) {
            if (index == 0) return 0x4138941D4b55b864ceC671E6737636107587c695;
            // Add more deployments here
        }
        revert("Bloom deployment not found for this index");
    }

    function getLastBloom(uint256 chainId) internal pure returns (address) {
        // Sepolia
        if (chainId == 11155111) {
            return 0x4138941D4b55b864ceC671E6737636107587c695; // latest deployment
        }
        revert("No Bloom deployment found for this network");
    }

    // ---------------- FEE CONTROLLER ----------------
    function getFeeController(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0x5e2CB57026c867726BDAa92C0C4866D599AAb4f9;
            // Add more deployments here
        }
        revert("FeeController deployment not found for this index");
    }

    function getLastFeeController(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0x5e2CB57026c867726BDAa92C0C4866D599AAb4f9; // latest deployment
        }
        revert("No FeeController deployment found for this network");
    }

    // ---------------- Bloom Escrow ----------------
     function getBloomEscrow(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0x834f25Ef3D695C888d0792F17024fe7F2fE0c822;
            // Add more deployments here
        }
        revert("FeeController deployment not found for this index");
    }

    function getLastBloomEscrow(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0x834f25Ef3D695C888d0792F17024fe7F2fE0c822; // latest deployment
        }
        revert("No FeeController deployment found for this network");
    }

     // ---------------- Juror Manager ----------------
     function getJurorManager(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0x834f25Ef3D695C888d0792F17024fe7F2fE0c822;
            // Add more deployments here
        }
        revert("FeeController deployment not found for this index");
    }

    function getLastJurorManager(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0x834f25Ef3D695C888d0792F17024fe7F2fE0c822; // latest deployment
        }
        revert("No FeeController deployment found for this network");
    }
     // ---------------- Dispute Storage ----------------
     function getDisputeStorage(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return address(0);
            // Add more deployments here
        }
        revert("Dispute storage deployment not found for this index");
    }

    function getLastDisputeStorage(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return address(0); // latest deployment
        }
        revert("No Dispute storage deployment found for this network");
    }
}
