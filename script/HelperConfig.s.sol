// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script, console2} from "forge-std/Script.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";
import {MockDAI} from "../test/mocks/MockDAI.sol";
import {MockWETH} from "../test/mocks/MockWETH.sol";

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
        address usdcTokenAddress;
        address daiTokenAddress;
        address wethTokenAddress;
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
            daiUsdPriceFeed: address(0),
            usdcTokenAddress: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
            daiTokenAddress: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
            wethTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        });
        return sepoliaConfig;
    }

    function getZkSyncSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory zkSyncSepoliaConfig = NetworkConfig({
            ethUsdPriceFeed: address(0),
            usdcUsdPriceFeed: address(0),
            daiUsdPriceFeed: address(0),
            usdcTokenAddress: address(0),
            daiTokenAddress: address(0),
            wethTokenAddress: address(0)
        });
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

        MockUSDC mockUsdc = new MockUSDC();
        MockDAI mockDai = new MockDAI();
        MockWETH mockWeth = new MockWETH();

        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: address(mockEthPriceFeed),
            usdcUsdPriceFeed: address(mockUsdcPriceFeed),
            daiUsdPriceFeed: address(mockDaiPriceFeed),
            usdcTokenAddress: address(mockUsdc),
            daiTokenAddress: address(mockDai),
            wethTokenAddress: address(mockWeth)
        });
        return localNetworkConfig;
    }

    // function getDeployer() external pure returns (address deployerAddress, uint256 privateKey) {
    //     // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    //     address deployer = vm.addr(deployerPrivateKey);

    //     return (deployer, deployerPrivateKey);
    // }
}
