// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {DeployBloom} from "../script/DeployBloom.s.sol";
import {Bloom} from "../src/token/Bloom.sol";


contract DeployloomTest is Test {

    DeployBloom deployBloom;
    Bloom bloom;

    function setUp() external {
        deployBloom = new DeployBloom();
        // bloom = deployBloom.run();
    }


    function testTransfer() external {


    }
}

