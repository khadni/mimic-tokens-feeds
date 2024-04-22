// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library TokenPricingUtils {
    error MimicTokenFeeds__ZeroMimicTokenPrice();

    uint256 private constant DECIMALS_MULTIPLIER = 1e18; // Multiplier to adjust for decimal places
    uint256 private constant USDC_6_TO_18_DECIMALS = 1e12; // Multiplier to adjust USDC from 6 to 18 decimals

    // We want to work with 18 decimal places, matching the common ERC-20 standard
    int256 private constant DECIMALS_ADJUSTMENT = 1e10; // To adjust from 8 to 18 decimals

    /**
     * @notice Retrieves the latest price from a given Chainlink Price Feed and adjusts it to have 18 decimal places.
     * @dev Fetches the latest price data using Chainlink's AggregatorV3Interface.
     * @param priceFeed The Chainlink Price Feed contract from which to fetch the latest price data.
     * @return The latest price from the given Chainlink Price Feed, adjusted to 18 decimal places.
     */
    function getPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        return uint256(answer * DECIMALS_ADJUSTMENT);
    }

    /**
     * @dev Calculates the USD equivalent of a given token amount based on the latest price from a Chainlink Price Feed.
     * @param _tokenAmount The amount of the token to convert to USD, with decimals considered.
     * @param _priceFeed The Chainlink Price Feed contract used to fetch the current token price in USD.
     * @return The USD equivalent of the specified token amount, adjusted for decimal places.
     */
    function convertTokensToUsd(uint256 _tokenAmount, AggregatorV3Interface _priceFeed)
        internal
        view
        returns (uint256)
    {
        uint256 tokenPrice = getPrice(_priceFeed);
        uint256 tokenPriceInUsd = (tokenPrice * _tokenAmount) / 1e18;
        return tokenPriceInUsd;
    }

    /**
     * @dev Given a USDC amount and a MimicToken price, calculates the equivalent amount of MimicTokens.
     * The calculation adjusts for decimal differences between USDC (6 decimals) and MimicTokens (18 decimals).
     * @param usdcAmount Amount of USDC to convert to MimicTokens, with USDC's 6 decimal places considered.
     * @param mimicTokenPrice Current price of one MimicToken in USDC, scaled to 18 decimal places for precision.
     * @return The calculated amount of MimicTokens that can be bought with the specified USDC amount, scaled to 18 decimal places.
     * @custom:error MimicTokenFeeds__ZeroMimicTokenPrice Triggered if the MimicToken price is provided as zero.
     */
    function calculateMimicTokenAmount(uint256 usdcAmount, uint256 mimicTokenPrice) internal pure returns (uint256) {
        if (mimicTokenPrice == 0) {
            revert MimicTokenFeeds__ZeroMimicTokenPrice();
        }

        uint256 mimicTokenAmount = (usdcAmount * USDC_6_TO_18_DECIMALS * DECIMALS_MULTIPLIER) / mimicTokenPrice;
        // usdcAmount = mimicTokenAmount * mimicTokenPrice / (1e12 * 1e18)

        return mimicTokenAmount;
    }

    /**
     * @dev Calculates the amount of USDC to give for a given amount of MimicTokens being sold.
     * @param mimicTokenAmount The amount of MimicTokens being sold.
     * @param mimicTokenPrice The current price of MimicToken in USD.
     * @return The amount of USDC to transfer to the seller.
     */
    function calculateUSDCAmount(uint256 mimicTokenAmount, uint256 mimicTokenPrice) internal pure returns (uint256) {
        // Calculate the amount of USDC to transfer.
        uint256 usdcAmount = ((mimicTokenAmount * mimicTokenPrice) / DECIMALS_MULTIPLIER) / USDC_6_TO_18_DECIMALS;
        return usdcAmount; // 6 decimals
    }
}
