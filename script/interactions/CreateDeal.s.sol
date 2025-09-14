//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BloomEscrow} from "../../src/core/escrow/BloomEscrow.sol";
import {FeeController} from "../../src/core/FeeController.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {console} from "forge-std/console.sol";
import {DeployedAddresses} from "../../script/deploy/DeployedAddresses.sol";
import {IERC20Mock} from "../../src/interfaces/IERC20Mock.sol";

contract CreateDeal is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);
        address bloomEscrowAddress = DeployedAddresses.getLastBloomEscrow(block.chainid);
        address feeControllerAddress = DeployedAddresses.getLastFeeController(block.chainid);

        address sender = 0xc3235B99Bdf0F12e793BcA9B83A8BAD88E06C8B3;
        address receiver = 0x1d011983F10E491662dd1eA8Af0D6d6213B76A85;
        address tokenAddress = networkConfig.usdcTokenAddress;
        uint256 amount = 100e6;

        BloomEscrow bloomEscrow = BloomEscrow(bloomEscrowAddress);
        FeeController feeController = FeeController(feeControllerAddress);

        uint256 escrowFee = feeController.calculateEscrowFee(amount);
        console.log("Escow fee: ", escrowFee);

        uint256 totalAmount = amount + escrowFee;
        console.log("Total amount: ", totalAmount);

        IERC20Mock token = IERC20Mock(tokenAddress);
        uint256 senderPrivateKey = vm.envUint("SENDER_PRIVATE_KEY");

        vm.startBroadcast(senderPrivateKey);
        token.approve(address(bloomEscrow), totalAmount);
        bloomEscrow.createDeal(sender, receiver, tokenAddress, amount);

        vm.stopBroadcast();
    }

}
