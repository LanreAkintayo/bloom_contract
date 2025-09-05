// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script, console2} from "forge-std/Script.sol";

abstract contract CodeConstants {
    // For ETH
    uint8 public constant ETH_DECIMALS = 18;
    int256 public constant ETH_INITIAL_PRICE = 4000e18;

    // For DAI
    uint8 public constant DAI_DECIMALS = 18;
    int256 public constant DAI_INITIAL_PRICE = 1e18;

    // For USDC
    uint8 public constant USDC_DECIMALS = 8;
    int256 public constant USDC_INITIAL_PRICE = 1e8;

    /*//////////////////////////////////////////////////////////////
                               CHAIN IDS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address ethUsdPriceFeed; // ETH/USD price feed address
        address usdcUsdPriceFeed; // USDC/USD price feed address
        address daiUsdPriceFeed; // DAI/USD price feed address
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Local network state variables
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    MockV3Aggregator mockEthPriceFeed;
    MockV3Aggregator mockUsdcPriceFeed;
    MockV3Aggregator mockDaiPriceFeed;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ZKSYNC_SEPOLIA_CHAIN_ID] = getZkSyncSepoliaConfig();
        // Note: We skip doing the local config
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].ethUsdPriceFeed != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            usdcUsdPriceFeed: address(0),
            daiUsdPriceFeed: address(0)
        });
        return sepoliaConfig;
    }

    function getZkSyncSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory zkSyncSepoliaConfig =
            NetworkConfig({ethUsdPriceFeed: address(0), usdcUsdPriceFeed: address(0), daiUsdPriceFeed: address(0)});
        return zkSyncSepoliaConfig;
    }

    /*//////////////////////////////////////////////////////////////
                              LOCAL CONFIG
    //////////////////////////////////////////////////////////////*/
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check to see if we set an active network config
        if (localNetworkConfig.ethUsdPriceFeed != address(0)) {
            return localNetworkConfig;
        }

        console2.log(unicode"⚠️ You have deployed a mock contract!");
        console2.log("Make sure this was intentional");
        vm.startBroadcast();

        mockUsdcPriceFeed = new MockV3Aggregator(USDC_DECIMALS, USDC_INITIAL_PRICE);
        mockEthPriceFeed = new MockV3Aggregator(ETH_DECIMALS, ETH_INITIAL_PRICE);
        mockDaiPriceFeed = new MockV3Aggregator(DAI_DECIMALS, DAI_INITIAL_PRICE);

        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: address(mockEthPriceFeed),
            usdcUsdPriceFeed: address(mockUsdcPriceFeed),
            daiUsdPriceFeed: address(mockDaiPriceFeed)
        });
        return localNetworkConfig;
    }
}
