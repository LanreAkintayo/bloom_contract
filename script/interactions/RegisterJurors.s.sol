//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FeeController} from "../../src/core/FeeController.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {console} from "forge-std/console.sol";
import {DeployedAddresses} from "../../script/deploy/DeployedAddresses.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Mock} from "../../src/interfaces/IERC20Mock.sol";
import {JurorManager} from "../../src/core/disputes/JurorManager.sol";

contract RegisterJurors is Script {
    function run() external  {

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfigByChainId(block.chainid);
  
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerWallet = 0xec2B1547294a4dd62C0aE651aEb01493f8e4cD74;
        // address[] memory jurorAddresses = new address[](1);
        // jurorAddresses[0] = 0xc3235B99Bdf0F12e793BcA9B83A8BAD88E06C8B3;
        address[] memory jurorAddresses = new address[](10);
        
        jurorAddresses[0] = 0xc3235B99Bdf0F12e793BcA9B83A8BAD88E06C8B3;
        jurorAddresses[1] = 0x1d011983F10E491662dd1eA8Af0D6d6213B76A85 ;
        jurorAddresses[2] = 0x8EA11de1130aA63aD0CD553B580fe0ca16C6fE06;
        jurorAddresses[3] = 0x38eF052F7cf9c84940E6ca0e3b98411e0c15Ee0a;
        jurorAddresses[4] = 0x5709666308b6d4a7129aCc66d2237beE65083097;
        jurorAddresses[5] = 0x4bE1d42471E6D6a078A28cf4f530A2F564100419;
        jurorAddresses[6] = 0x91FF08D659A2bF96dF7F7b5e290677a133Ed81B5;
        jurorAddresses[7] = 0x77D5f1995B2Ef0bF3DfF06bbb1943F54c644AE7f;
        jurorAddresses[8] = 0x6AeCa04B7208d65B35aAa53061Bd3d6b348fe72f;
        jurorAddresses[9] = 0xE96fe7aD34B1a276C7cBc8ec1b0dB4866976FcA4;

        uint256 stakeAmount = 10_000e18;
        address bloomTokenAddress = networkConfig.bloomTokenAddress;
        address bloomEscrowAddress = DeployedAddresses.getLastBloomEscrow(block.chainid);
        address jurorManagerAddress = DeployedAddresses.getLastJurorManager(block.chainid);

        IERC20Mock bloomTokenContract = IERC20Mock(bloomTokenAddress);
        JurorManager jurorManager = JurorManager(jurorManagerAddress);


        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < jurorAddresses.length; i++) {
            console.log("Registering juror: ", jurorAddresses[i]);
            address currentJuror = jurorAddresses[i];

           jurorManager.registerJuror(stakeAmount);
        }
        vm.stopBroadcast();       
    }
}
