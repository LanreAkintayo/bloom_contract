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
    uint256 public constant MAINNET_CHAIN_ID = 1;
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
        address wrappedNativeTokenAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Local network state variables
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;
    VRFCoordinatorV2Mock public vrfCoordinator;
    VRFV2Wrapper public wrapper;

    // MockV3Aggregator mockEthPriceFeed;
    // MockV3Aggregator mockUsdcPriceFeed;
    // MockV3Aggregator mockDaiPriceFeed;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ZKSYNC_SEPOLIA_CHAIN_ID] = getZkSyncSepoliaConfig();
        networkConfigs[ZKSYNC_SEPOLIA_CHAIN_ID] = getZkSyncSepoliaConfig();
        networkConfigs[MAINNET_CHAIN_ID] = getSepoliaEthConfig();
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
            usdcUsdPriceFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E,
            daiUsdPriceFeed: 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19,
            usdcTokenAddress: 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8, //6
            daiTokenAddress: 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357,
            wethTokenAddress: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c,
            linkAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            wrapperAddress: 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46,
            bloomTokenAddress: 0xc4E523B7d26186eC7f1dCBed8a64DaBDE795C98E,
            wrappedNativeTokenAddress: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
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
            bloomTokenAddress: address(0),
            wrappedNativeTokenAddress: address(0)
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
            VRFV2Wrapper vrfV2Wrapper,
            VRFCoordinatorV2Mock _vrfCoordinator
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
            bloomTokenAddress: address(bloom),
            wrappedNativeTokenAddress: address(weth)
        });

        vrfCoordinator = _vrfCoordinator;
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
        returns (LinkToken, VRFV2Wrapper, VRFCoordinatorV2Mock)
    {
        // Mock base fee (minimum payment to request randomness)
        uint96 baseFee = 0.1 ether;

        // Mock gas price for LINK
        uint96 gasPriceLink = 1 gwei;

        // Deploy a mock VRF coordinator
        VRFCoordinatorV2Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);

        // Deploy a mock LINK token
        LinkToken link = new LinkToken();
        link.grantMintRole(address(this));

        // Deploy a mock VRF V2 wrapper with coordinator, LINK, and ETH price feed
        wrapper = new VRFV2Wrapper(
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
        return (link, wrapper, vrfCoordinatorV2Mock);
    }


    function getVRFCoordinator() external view returns (VRFCoordinatorV2Mock) {
        return vrfCoordinator;
    }

    function getVRFV2Wrapper() external view returns (VRFV2Wrapper) {
        return wrapper;
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
