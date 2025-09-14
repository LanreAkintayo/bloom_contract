//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BloomEscrow} from "../../src/core/escrow/BloomEscrow.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {console} from "forge-std/console.sol";
import {DeployedAddresses} from "../../script/deploy/DeployedAddresses.sol";

contract SetupBloomEscrow is Script {
    function run() external  {
         HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);
        address bloomEscrowAddress = DeployedAddresses.getLastBloomEscrow(block.chainid);
        address feeControllerAddress = DeployedAddresses.getLastFeeController(block.chainid);
        address disputeManagerAddress = DeployedAddresses.getLastDisputeManager(block.chainid);

        BloomEscrow bloomEscrow = BloomEscrow(bloomEscrowAddress);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        bloomEscrow.addFeeController(feeControllerAddress);
        bloomEscrow.addDisputeManager(disputeManagerAddress);

        bloomEscrow.addToken(networkConfig.usdcTokenAddress);
        bloomEscrow.addToken(networkConfig.daiTokenAddress);
        bloomEscrow.addToken(networkConfig.wethTokenAddress);

        vm.stopBroadcast();

       
    }
}
