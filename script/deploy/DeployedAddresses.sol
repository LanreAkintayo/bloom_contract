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
            return 0x0De2fBE02b6D68FC92784ccae46A127c5E17c48C; // latest deployment
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
            return 0x833323b50e6Bd3063835C6534DA38bCc0eb19845; // latest deployment
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
            return 0x4e3074E3c1eDC632eD0755658FBdD46F29830D01; // latest deployment
        }
        revert("No FeeController deployment found for this network");
    }

     // ---------------- Juror Manager ----------------
     function getJurorManager(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0xcBB6C09Bf38AC494F54F19A0C18cc4727A47e29E;
            // Add more deployments here
        }
        revert("FeeController deployment not found for this index");
    }

    function getLastJurorManager(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0xEd665981988b6Ad8Dfb05Dd380EEcD44C933e415; // latest deployment
        }
        revert("No FeeController deployment found for this network");
    }
     // ---------------- Dispute Storage ----------------
     function getDisputeStorage(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0xc550bf851EC14F163AEcEfB2383bAFA78e9968C1;
            // Add more deployments here
        }
        revert("Dispute storage deployment not found for this index");
    }

    function getLastDisputeStorage(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0x3942B4b553c2E376B1104B715531B724d9f5f547; // latest deployment
        }
        revert("No Dispute storage deployment found for this network");
    }
     // ---------------- Dispute Manager ----------------
     function getDisputeManager(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0xf1587D5265eb6147D4f4E758c01b0e9BD460e8fc;
            // Add more deployments here
        }
        revert("Dispute manager deployment not found for this index");
    }

    function getLastDisputeManager(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0x167883e884087b7eC704C07CD5e0d593ABDafA9C; // latest deployment
        }
        revert("No Dispute manager deployment found for this network");
    }
     // ---------------- Helper Config ----------------
     function getHelperConfig(uint256 chainId, uint256 index) internal pure returns (address) {
        if (chainId == 11155111) {
            if (index == 0) return 0x5aAdFB43eF8dAF45DD80F4676345b7676f1D70e3;
            // Add more deployments here
        }
        revert("Helper config deployment not found for this index");
    }

    function getLastHelperConfig(uint256 chainId) internal pure returns (address) {
        if (chainId == 11155111) {
            return 0x5aAdFB43eF8dAF45DD80F4676345b7676f1D70e3; // latest deployment
        }
        revert("No Helper config deployment found for this network");
    }
}
