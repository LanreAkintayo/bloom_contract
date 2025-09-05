// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployFeeController} from "../script/DeployFeeController.s.sol";
import {FeeController} from "../src/core/FeeController.sol";
import {Bloom} from "../src/token/Bloom.sol";


contract FeeControllerTest is Test {

    DeployFeeController deployFeeController;
    FeeController feeController;

    function setUp() external {
        deployFeeController = new DeployFeeController();
        // feeController = deployFeeController.run();
    }


    function testTransfer() external {


    }
}

