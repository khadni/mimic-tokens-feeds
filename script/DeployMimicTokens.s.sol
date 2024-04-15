// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MimicTokenFeeds} from "../src/MimicTokenFeeds.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMimicTokens is Script {
    using stdJson for string;

    uint256 public constant INITIAL_SUPPLY = 1000000 ether; // 1 million tokens with 18 decimal places
    uint256 private deployerKey;

    function run() external returns (MimicTokenFeeds, MimicTokenFeeds, MimicTokenFeeds, MimicTokenFeeds) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address usdcAddress,
            address btcPriceFeed,
            address ethPriceFeed,
            address linkPriceFeed,
            address xauPriceFeed,
            address registrarAddress,
            address linkTokenAddress
        ) =
        // deployerKey
         helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        MimicTokenFeeds mimicBTC = new MimicTokenFeeds(
            "MimicBTC", "mBTC", INITIAL_SUPPLY, usdcAddress, btcPriceFeed, registrarAddress, linkTokenAddress
        );
        MimicTokenFeeds mimicETH = new MimicTokenFeeds(
            "MimicETH", "mETH", INITIAL_SUPPLY, usdcAddress, ethPriceFeed, registrarAddress, linkTokenAddress
        );
        MimicTokenFeeds mimicLINK = new MimicTokenFeeds(
            "MimicLINK", "mLINK", INITIAL_SUPPLY, usdcAddress, linkPriceFeed, registrarAddress, linkTokenAddress
        );
        MimicTokenFeeds mimicXAU = new MimicTokenFeeds(
            "MimicXAU", "mXAU", INITIAL_SUPPLY, usdcAddress, xauPriceFeed, registrarAddress, linkTokenAddress
        );
        vm.stopBroadcast();

        string memory jsonObj = "internal_key";

        vm.serializeAddress(jsonObj, "mimicBTC", address(mimicBTC));
        vm.serializeAddress(jsonObj, "mimicETH", address(mimicETH));
        vm.serializeAddress(jsonObj, "mimicLINK", address(mimicLINK));
        string memory finalJson = vm.serializeAddress(jsonObj, "mimicXAU", address(mimicXAU));

        console.log(finalJson);

        vm.writeJson(finalJson, "./output/deployedMimicTokensFeeds.json");

        return (mimicBTC, mimicETH, mimicLINK, mimicXAU);
    }
}
