// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MimicTokenFeeds} from "../src/MimicTokenFeeds.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySingleMimicToken is Script {
    using stdJson for string;

    uint256 public constant INITIAL_SUPPLY = 1000000 ether; // 1 million tokens with 18 decimal places
    uint256 private deployerKey;

    function run() external returns (MimicTokenFeeds) {
        HelperConfig helperConfig = new HelperConfig();
        (address usdcAddress,,, address linkPriceFeed,, address registrarAddress, address linkTokenAddress) =
        // deployerKey
         helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        MimicTokenFeeds mimicLINK = new MimicTokenFeeds(
            "MimicLINK", "mLINK", INITIAL_SUPPLY, usdcAddress, linkPriceFeed, registrarAddress, linkTokenAddress
        );
        vm.stopBroadcast();

        string memory jsonObj = "internal_key";

        string memory finalJson = vm.serializeAddress(jsonObj, "mimicLINK", address(mimicLINK));

        console.log(finalJson);

        vm.writeJson(finalJson, "./output/deployedMimicTokensFeeds.json");

        return (mimicLINK);
    }
}
