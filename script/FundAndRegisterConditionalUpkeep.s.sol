// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {MimicTokenFeeds} from "../src/MimicTokenFeeds.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract FundAndRegisterConditionalUpkeep is Script {
    MimicTokenFeeds public mimicTokenFeed;
    LinkTokenInterface public i_link;
    HelperConfig public helperConfig;
    uint256 public constant LINK_AMOUNT_TO_TRANSFER = 1e18; // 1 LINK
    address public mimicTokenAddress = 0x42E45a9f042dF73F36cf454910E11062e7c81f8c;

    // Set these addresses before deploying the script
    address public registrarAddress; // Address of the AutomationRegistrar contract.
    address public linkTokenAddress; // Address of the LINK token contract.
    // uint256 private deployerKey; // Key of the deployer account.

    function run() external {
        // Initialize the HelperConfig contract
        helperConfig = new HelperConfig();

        // Retrieve network-specific addresses from HelperConfig
        (,,,,, registrarAddress, linkTokenAddress) = helperConfig.activeNetworkConfig();

        i_link = LinkTokenInterface(linkTokenAddress);

        // Retrieve the deployed MimicToken contract instance
        mimicTokenFeed = MimicTokenFeeds(mimicTokenAddress);

        vm.startBroadcast();

        // Run the selfRegisterAndFundForConditionalUpkeep function on the MimicToken contract to register the upkeep
        console.log("Registering upkeep...");
        console.log(msg.sender);
        mimicTokenFeed.selfRegisterAndFundForConditionalUpkeep();
        console.log("Upkeep registered with ID");
        vm.stopBroadcast();
    }
}
