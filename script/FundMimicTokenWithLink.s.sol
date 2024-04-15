// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract FundMimicTokenWithLink is Script {
    using stdJson for string;

    LinkTokenInterface public i_link;
    uint256 public constant LINK_AMOUNT_TO_TRANSFER = 1000000000000000000; // 1 LINK

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/output/deployedMimicTokensFeeds.json");
        string memory json = vm.readFile(path);

        address mimicBTCAddress = json.readAddress(".mimicBTC");
        address mimicETHAddress = json.readAddress(".mimicETH");
        address mimicLINKAddress = json.readAddress(".mimicLINK");
        address mimicAUXAddress = json.readAddress(".mimicXAU");

        HelperConfig helperConfig = new HelperConfig();
        (,,,,,, address linkTokenAddress) = helperConfig.activeNetworkConfig();

        i_link = LinkTokenInterface(linkTokenAddress);

        vm.startBroadcast();

        // Transfer LINK tokens to the mimicBTC contract
        bool successTransferToMBTC = i_link.transfer(mimicBTCAddress, LINK_AMOUNT_TO_TRANSFER);
        require(successTransferToMBTC, "Failed to transfer LINK tokens to mimicBTC contract");
        console.log("Transferred", LINK_AMOUNT_TO_TRANSFER, "LINK to mimicBTC contract at", mimicBTCAddress);

        // Transfer LINK tokens to the mimicETH contract
        bool successTransferToMETH = i_link.transfer(mimicETHAddress, LINK_AMOUNT_TO_TRANSFER);
        require(successTransferToMETH, "Failed to transfer LINK tokens to mimicETH contract");
        console.log("Transferred", LINK_AMOUNT_TO_TRANSFER, "LINK to mimicETH contract at", mimicETHAddress);

        // Transfer LINK tokens to the mimicLINK contract
        bool successTransferToMLINK = i_link.transfer(mimicLINKAddress, LINK_AMOUNT_TO_TRANSFER);
        require(successTransferToMLINK, "Failed to transfer LINK tokens to mimicLINK contract");
        console.log("Transferred", LINK_AMOUNT_TO_TRANSFER, "LINK to mimicLINK contract at", mimicLINKAddress);

        // Transfer LINK tokens to the mimicLINK contract
        bool successTransferToMXAU = i_link.transfer(mimicAUXAddress, LINK_AMOUNT_TO_TRANSFER);
        require(successTransferToMXAU, "Failed to transfer LINK tokens to mimicXAU contract");
        console.log("Transferred", LINK_AMOUNT_TO_TRANSFER, "LINK to mimicXAU contract at", mimicLINKAddress);

        vm.stopBroadcast();
    }
}
