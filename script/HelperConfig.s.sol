// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    // If we are on a local Anvil, we deploy the mocks
    // Else, grab the existing address from the live network

    struct NetworkConfig {
        address ethUsdPriceFeed; // ETH/USD price feed address
    }

    NetworkConfig public activeNetworkConfig;
    MockV3Aggregator mockPriceFeed;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig =
            NetworkConfig({ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306});
        return sepoliaConfig;
    }

    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        // Deploy mock price feed here;
        vm.startBroadcast();
        mockPriceFeed = new MockV3Aggregator(8, 2000e8);
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({ethUsdPriceFeed: address(mockPriceFeed)});
        return anvilConfig;
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
