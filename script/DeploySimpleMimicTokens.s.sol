// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SimpleMimicToken} from "../src/SimpleMimicToken.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMimicTokens is Script {
    using stdJson for string;

    uint256 public constant INITIAL_SUPPLY = 1000000 ether; // 1 million tokens with 18 decimal places
    uint256 private deployerKey;

    function run() external returns (SimpleMimicToken, SimpleMimicToken, SimpleMimicToken) {
        HelperConfig helperConfig = new HelperConfig();
        (address usdcAddress, address btcPriceFeed, address ethPriceFeed,, address xauPriceFeed,,) =
        // deployerKey
         helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        SimpleMimicToken mimicBTC =
            new SimpleMimicToken("MimicWBTC", "mWBTC", INITIAL_SUPPLY, usdcAddress, btcPriceFeed);
        SimpleMimicToken mimicETH = new SimpleMimicToken("MimicETH", "mETH", INITIAL_SUPPLY, usdcAddress, ethPriceFeed);
        SimpleMimicToken mimicXAU = new SimpleMimicToken("MimicXAU", "mXAU", INITIAL_SUPPLY, usdcAddress, xauPriceFeed);
        vm.stopBroadcast();

        string memory jsonObj = "internal_key";

        vm.serializeAddress(jsonObj, "mimicWBTC", address(mimicBTC));
        vm.serializeAddress(jsonObj, "mimicETH", address(mimicETH));
        string memory finalJson = vm.serializeAddress(jsonObj, "mimicXAU", address(mimicXAU));

        console.log(finalJson);

        vm.writeJson(finalJson, "./output/deployedMimicTokensFeeds.json");

        return (mimicBTC, mimicETH, mimicXAU);
    }
}
