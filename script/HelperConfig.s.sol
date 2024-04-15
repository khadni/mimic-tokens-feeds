// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE_BTC = 60000e8;
    int256 public constant INITIAL_PRICE_ETH = 3000e8;
    int256 public constant INITIAL_PRICE_LINK = 20e8;
    int256 public constant INITIAL_PRICE_XAU = 2500e8;
    // int256 public constant INITIAL_PRICE_ = 20e8;

    struct NetworkConfig {
        address usdcAddress;
        address btcPriceFeed;
        address ethPriceFeed;
        address linkPriceFeed;
        address xauPriceFeed;
        address registrarAddress;
        address linkTokenAddress;
    }
    // uint256 deployerKey;

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getEthereumSepoliaConfig();

            // } else if (block.chainid == 421614) {
            //     activeNetworkConfig = getArbitrumSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getEthereumSepoliaConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory ethereumSepoliaConfig = NetworkConfig({
            usdcAddress: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC token contract address
            btcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC/USD price feed address
            ethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH/USD price feed address
            linkPriceFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF, // LINK/USD price feed address
            xauPriceFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea, // XAU/USD price feed address
            registrarAddress: 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976, // AutomationRegistrar contract address
            linkTokenAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789 // LINK token contract address
                // deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return ethereumSepoliaConfig;
    }

    // function getArbitrumSepoliaConfig() public view returns (NetworkConfig memory) {
    //     NetworkConfig memory arbitrumSepoliaConfig = NetworkConfig({
    //         btcPriceFeed: 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69, // BTC/USD price feed address
    //         ethPriceFeed: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165, // ETH/USD price feed address
    //         linkPriceFeed: 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298, // LINK/USD price feed address
    //         registrarAddress: 0x881918E24290084409DaA91979A30e6f0dB52eBe, // AutomationRegistrar contract address
    //         linkTokenAddress: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E, // LINK token contract address
    //         deployerKey: vm.envUint("PRIVATE_KEY")
    //     });
    //     return arbitrumSepoliaConfig;
    // }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (
            activeNetworkConfig.btcPriceFeed != address(0) && activeNetworkConfig.ethPriceFeed != address(0)
                && activeNetworkConfig.linkPriceFeed != address(0)
        ) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator mockPriceFeedBtc = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_BTC);
        MockV3Aggregator mockPriceFeedEth = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_ETH);
        MockV3Aggregator mockPriceFeedLink = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_LINK);
        MockV3Aggregator mockPriceFeedXau = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_XAU);
        vm.stopBroadcast();

        // TBD!!
        NetworkConfig memory anvilConfig = NetworkConfig({
            usdcAddress: address(0),
            btcPriceFeed: address(mockPriceFeedBtc),
            ethPriceFeed: address(mockPriceFeedEth),
            linkPriceFeed: address(mockPriceFeedLink),
            xauPriceFeed: address(mockPriceFeedXau),
            registrarAddress: address(0),
            linkTokenAddress: address(0)
        });
        // deployerKey: DEFAULT_ANVIL_PRIVATE_KEY

        return anvilConfig;
    }
}
