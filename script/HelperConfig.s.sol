// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script, console2} from "forge-std/Script.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";
import {MockDAI} from "../test/mocks/MockDAI.sol";
import {MockWETH} from "../test/mocks/MockWETH.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "@chainlink/contracts/src/v0.8/shared/token/ERC677/LinkToken.sol";
import {VRFV2Wrapper} from "@chainlink/contracts/src/v0.8/vrf/VRFV2Wrapper.sol";
import {Bloom} from "../src/token/Bloom.sol";

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
        address linkAddress;
        address wrapperAddress;
        address bloomTokenAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Local network state variables
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    // MockV3Aggregator mockEthPriceFeed;
    // MockV3Aggregator mockUsdcPriceFeed;
    // MockV3Aggregator mockDaiPriceFeed;

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
            wethTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            linkAddress: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            wrapperAddress: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            bloomTokenAddress: address(0)
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
            wethTokenAddress: address(0),
            linkAddress: address(0),
            wrapperAddress: address(0),
            bloomTokenAddress: address(0)
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

        // Deploy Bloom
        Bloom bloom = new Bloom();
      
        // Deploy price feeds;
        (MockV3Aggregator mockUsdcPriceFeed, MockV3Aggregator mockEthPriceFeed, MockV3Aggregator mockDaiPriceFeed) =
            _deployPriceFeeds();

        // Deploy mock tokens
        (MockUSDC usdc, MockDAI dai, MockWETH weth) = _deployMockTokens();

        (
            LinkToken linkToken,
            VRFV2Wrapper vrfV2Wrapper
        ) = _setUpVRF(address(mockEthPriceFeed));

        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: address(mockEthPriceFeed),
            usdcUsdPriceFeed: address(mockUsdcPriceFeed),
            daiUsdPriceFeed: address(mockDaiPriceFeed),
            usdcTokenAddress: address(usdc),
            daiTokenAddress: address(dai),
            wethTokenAddress: address(weth),
            linkAddress: address(linkToken),
            wrapperAddress: address(vrfV2Wrapper),
            bloomTokenAddress: address(bloom)
        });
        return localNetworkConfig;
    }

    function _deployPriceFeeds()
        internal
        returns (MockV3Aggregator usdcFeed, MockV3Aggregator ethFeed, MockV3Aggregator daiFeed)
    {
        MockV3Aggregator mockUsdcPriceFeed = new MockV3Aggregator(USDC_DECIMALS, USDC_INITIAL_PRICE);
        MockV3Aggregator mockEthPriceFeed = new MockV3Aggregator(ETH_DECIMALS, ETH_INITIAL_PRICE);
        MockV3Aggregator mockDaiPriceFeed = new MockV3Aggregator(DAI_DECIMALS, DAI_INITIAL_PRICE);

        return (mockUsdcPriceFeed, mockEthPriceFeed, mockDaiPriceFeed);
    }

    function _deployMockTokens() internal returns (MockUSDC usdc, MockDAI dai, MockWETH weth) {
        MockUSDC mockUsdc = new MockUSDC();
        MockDAI mockDai = new MockDAI();
        MockWETH mockWeth = new MockWETH();
        return (mockUsdc, mockDai, mockWeth);
    }

    function _setUpVRF(address ethPriceFeed)
        internal
        returns (LinkToken linkToken, VRFV2Wrapper vrfV2Wrapper)
    {
        // Mock base fee (minimum payment to request randomness)
        uint96 baseFee = 0.1 ether;

        // Mock gas price for LINK
        uint96 gasPriceLink = 1 gwei;

        // Deploy a mock VRF coordinator
        VRFCoordinatorV2Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);

        // Deploy a mock LINK token
        LinkToken link = new LinkToken();

        // Deploy a mock VRF V2 wrapper with coordinator, LINK, and ETH price feed
        VRFV2Wrapper wrapper = new VRFV2Wrapper(
            address(link),
            ethPriceFeed,
            address(vrfCoordinatorV2Mock)
        );

        // Wrapper configuration parameters
        uint32 wrapperGasOverhead = 60000;        // Gas overhead for wrapper execution
        uint32 coordinatorGasOverhead = 52000;    // Gas overhead for coordinator execution
        uint8 wrapperPremiumPercentage = 10;      // Premium % added to VRF costs
        bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // Mock key hash
        uint8 maxNumWords = 10;                   // Max random words in a single request

        // Apply wrapper configuration
        wrapper.setConfig(
            wrapperGasOverhead,
            coordinatorGasOverhead,
            wrapperPremiumPercentage,
            keyHash,
            maxNumWords
        );

        // Fund the subscription so VRF requests can succeed
        uint64 subId = 1;
        uint96 amount = 10 ether;
        vrfCoordinatorV2Mock.fundSubscription(subId, amount);

        // Return the deployed contracts
        return (link, wrapper);
    }

    function setUpRandomNumberStuff() external {
        /**
         * // Deploy VRFCoordinatorV2Mock and set BASEFEE to 100000000000000000 and GASPRICELINK to 1000000000
         *
         *     // Deploy LnkToken
         *
         *     // Deploy VRFV2Wrapper. It takes in the address _link, address _linkEthFeed (the MockV3Aggregator contract address), address _coordinator (VRFCoordinatorV2Mock)
         *
         *     // Call setConfig in VRFV2Wrapper
         *      function setConfig(
         *         uint32 _wrapperGasOverhead = 60000
         *         uint32 _coordinatorGasOverhead = 52000
         *         uint8 _wrapperPremiumPercentage = 10
         *         bytes32 _keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc
         *         uint8 _maxNumWords = 10
         *     )
         *
         *     // In the VRFCoordinatorV2Mock, call fundSubscription
         *      fundSubscription(uint64 _subId = 1, uint96 _amount = 10000000000000000000)
         *
         *      The address of the VRFV2Wrapper and the linkAddress will now be sent to the JurorManager
         *
         *      // We then send LINK token to the JurorManager contract
         *
         *
         *      // To request for random words, _callbackGasLimit = 300000 and _requestConfirmations = 3, numWords = 1
         *
         *      //Because we are on local network, we should call the fulfillRandomWords ourselves. We call the fulfillRandomWords function in the VRFCoordinatorV2Mock
         *      function fulfillRandomWords(uint256 _requestId, address _consumer). We have to somehow get the requestId in the JurorManager. Consumer is the JurorManager contract
         */
    }
}
