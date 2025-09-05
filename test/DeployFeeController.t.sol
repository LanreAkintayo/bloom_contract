// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployFeeController} from "../script/DeployFeeController.s.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {Bloom} from "../src/token/Bloom.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";


contract FeeControllerTest is Test {

    DeployFeeController deployFeeController;
    FeeController feeController;
    HelperConfig helperConfig;

    function setUp() external {
        deployFeeController = new DeployFeeController();
        (feeController, helperConfig) = deployFeeController.run();
    }


    function testCalculateEscrowFee() external view {
        uint256 amount = 100e18;
        uint256 escrowFee = feeController.calculateEscrowFee(amount);

        assertEq(escrowFee, 1e18);

    }
}

