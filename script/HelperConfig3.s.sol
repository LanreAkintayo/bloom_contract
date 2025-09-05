// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    // If we are on a local Anvil, we deploy the mocks
    // Else, grab the existing address from the live network

    struct NetworkConfig {
        address ethUsdPriceFeed; // ETH/USD price feed address
        address usdcUsdPriceFeed; // USDC/USD price feed address
        address daiUsdPriceFeed; // DAI/USD price feed address
    }

    NetworkConfig public activeNetworkConfig;
    MockV3Aggregator mockEthPriceFeed;
    MockV3Aggregator mockUsdcPriceFeed;
    MockV3Aggregator mockDaiPriceFeed;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            usdcUsdPriceFeed: address(0),
            daiUsdPriceFeed: address(0)
        });
        return sepoliaConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {

        // No need to deploy mocks if they've already been deployed;
        if (activeNetworkConfig.ethUsdPriceFeed != address(0)) {
            return activeNetworkConfig  ;
        }

        // Deploy mock price feed here;
        vm.startBroadcast();
        mockUsdcPriceFeed = new MockV3Aggregator(8, 1);
        mockEthPriceFeed = new MockV3Aggregator(18, 4000);
        mockDaiPriceFeed = new MockV3Aggregator(18, 1);
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            ethUsdPriceFeed: address(mockEthPriceFeed),
            usdcUsdPriceFeed: address(mockUsdcPriceFeed),
            daiUsdPriceFeed: address(mockDaiPriceFeed)
        });
        return anvilConfig;
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
