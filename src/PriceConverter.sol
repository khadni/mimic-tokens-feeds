// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library PriceConverter {
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
        // Ensure answer is not negative before casting to uint256
        require(answer >= 0, "Price is negative");
        return uint256(answer * DECIMALS_ADJUSTMENT);
    }

    /**
     * @dev Calculates the USD equivalent of a given token amount based on the latest price from a Chainlink Price Feed.
     * @param _tokenAmount The amount of the token to convert to USD, with decimals considered.
     * @param _priceFeed The Chainlink Price Feed contract used to fetch the current token price in USD.
     * @return The USD equivalent of the specified token amount, adjusted for decimal places.
     */
    function getConversionRate(uint256 _tokenAmount, AggregatorV3Interface _priceFeed)
        internal
        view
        returns (uint256)
    {
        uint256 tokenPrice = getPrice(_priceFeed);
        uint256 tokenPriceInUsd = (tokenPrice * _tokenAmount) / 1e18;
        return tokenPriceInUsd;
    }
}
