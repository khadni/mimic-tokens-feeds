// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {AutomationRegistrarInterface, RegistrationParams} from "./interfaces/AutomationRegistrarInterface.sol";
import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

contract MimicTokenFeeds is ERC20, AutomationCompatibleInterface, ReentrancyGuard, Ownable {
    error MimicTokenFeeds__InsufficientLinkBalance(uint256 available, uint256 required);
    error MimicTokenFeeds__LinkApprovalFailed();
    error MimicTokenFeeds__NoLinkBalanceToWithdraw();
    error MimicTokenFeeds__NoUsdcBalanceToWithdraw();
    error MimicTokenFeeds__InsufficientUsdcAllowance(uint256 currentAllowance, uint256 requiredAllowance);
    error MimicTokenFeeds__InsufficientTokensInContract(uint256 requested, uint256 available);
    error MimicTokenFeeds__InsufficientUSDCInContract(uint256 requested, uint256 available);
    error MimicTokenFeeds__ZeroMimicTokenPrice();
    error MimicTokenFeeds__ZeroMimicTokenAmount();
    error MimicTokenFeeds__LinkTransferFailed();

    using PriceConverter for uint256;
    using SafeERC20 for IERC20;

    IERC20 private immutable s_usdc;
    AggregatorV3Interface private s_priceFeed;
    LinkTokenInterface private immutable i_link;
    AutomationRegistrarInterface private immutable i_registrar;

    uint96 private constant INIT_UPKEEP_FUNDING_AMOUNT = 1e18; // 1 LINK
    uint256 private constant DECIMALS_MULTIPLIER = 1e18; // Multiplier to adjust for decimal places
    uint256 private constant USDC_6_TO_18_DECIMALS = 1e12; // Multiplier to adjust USDC from 6 to 18 decimals
    uint256 private constant PERCENTAGE_MULTIPLIER = 10000; // Basis points multiplier to represent percentages with precision
    uint256 private constant MIN_UPDATE_INTERVAL = 1800; // Minimum time between updates in seconds
    uint256 private constant MIN_PRICE_DEVIATION_BPS = 50; // Minimum price deviation for upkeep trigger (0.5% deviation)
    uint256 private s_upkeepID;
    uint256 private s_lastTokenPriceUpdateTime;
    uint256 private s_lastTokenPriceInUsd;

    event PriceUpdated(uint256 newPrice, uint256 timestamp, string reason);
    event CustomUpkeepRegistered(uint256 upkeepID, address contractAddress, address admin);

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address usdcAddress,
        address priceFeedAddress,
        address registrarAddress,
        address linkTokenAddress
    ) ERC20(name, symbol) Ownable() {
        _mint(address(this), initialSupply);
        s_usdc = IERC20(usdcAddress);
        s_priceFeed = AggregatorV3Interface(priceFeedAddress);
        i_link = LinkTokenInterface(linkTokenAddress);
        i_registrar = AutomationRegistrarInterface(registrarAddress);
        s_lastTokenPriceUpdateTime = block.timestamp;
        s_lastTokenPriceInUsd = PriceConverter.getPrice(s_priceFeed);
    }

    /**
     * @notice Registers this contract for Chainlink Automation and funds it with LINK for upkeep costs.
     * @dev Self-registers the contract with the Chainlink Automation network, setting up conditions for automated upkeep.
     * It requires enough LINK tokens in the contract for the registration fee. This function sets up the initial parameters
     * for the upkeep, approves the necessary LINK tokens for the Automation Registrar, and then calls the registrar to register
     * the upkeep. It reverts if there's insufficient LINK balance or if LINK token approval fails.
     * Emits a `CustomUpkeepRegistered` event upon successful registration.
     * @return upkeepID The ID assigned to the registered upkeep by the Chainlink Automation Registrar.
     */
    function selfRegisterAndFundForConditionalUpkeep() external onlyOwner returns (uint256) {
        RegistrationParams memory params = RegistrationParams({
            name: "MimicTokenFeeds Upkeep",
            encryptedEmail: "0x", // Leave as 0x if not using email notifications
            upkeepContract: address(this), // This contract's address
            gasLimit: 500000, // Adjust based on your `performUpkeep` gas usage
            adminAddress: owner(), // Owner's address for upkeep management
            triggerType: 0, // Use 0 for conditional-based triggers
            checkData: "0x", // Optional: data for `checkUpkeep`
            triggerConfig: "0x", // Not used for time-based triggers
            offchainConfig: "0x", // Placeholder for future use
            amount: INIT_UPKEEP_FUNDING_AMOUNT // The initial funding amount in LINK (In WEI) - Ensure this is less than or equal to the allowance granted to the Automation Registrar
        });

        // Ensure the contract has enough LINK to cover the registration fee
        uint256 linkBalance = i_link.balanceOf(address(this));
        if (linkBalance < params.amount) {
            revert MimicTokenFeeds__InsufficientLinkBalance(linkBalance, params.amount);
        }

        // Approve the Chainlink Automation Registrar to use the contract's LINK tokens
        bool approvalSuccess = i_link.approve(address(i_registrar), params.amount);
        if (!approvalSuccess) {
            revert MimicTokenFeeds__LinkApprovalFailed();
        }

        // Call the `registerUpkeep` function on the Chainlink Automation Registrar
        uint256 upkeepID = i_registrar.registerUpkeep(params);

        // Store the returned upkeepID if needed for future reference
        s_upkeepID = upkeepID;

        emit CustomUpkeepRegistered(upkeepID, address(this), owner());

        return upkeepID;
    }

    /**
     * @notice Checks if upkeep is needed based on the token price deviation or the time since the last update.
     * @dev Calculates the current price deviation and the time since the last update to determine if upkeep is necessary. Upkeep is needed if the
     * price deviation exceeds a predefined threshold or if a certain amount of time has passed since the last update. The function returns a boolean
     * indicating whether upkeep is needed and encodes the current price and the reason for upkeep into `performData`.
     * param `checkData` Currently unused. Intended for future use where additional data might be needed for upkeep checks.
     * @return upkeepNeeded A boolean value indicating whether upkeep is needed.
     * @return performData Encoded data containing the current price and the reason for the upkeep. Decoded by `performUpkeep` when executing the upkeep.
     */
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 tempCurrentPrice = PriceConverter.getPrice(s_priceFeed);
        uint256 timeSinceLastUpdate = block.timestamp - s_lastTokenPriceUpdateTime;
        uint256 priceDeviation =
            (absDiff(s_lastTokenPriceInUsd, tempCurrentPrice) * PERCENTAGE_MULTIPLIER) / s_lastTokenPriceInUsd;

        bool isTimeConditionMet = timeSinceLastUpdate >= MIN_UPDATE_INTERVAL;
        bool isPriceConditionMet = priceDeviation >= MIN_PRICE_DEVIATION_BPS;

        upkeepNeeded = isTimeConditionMet || isPriceConditionMet;

        string memory reason = isTimeConditionMet ? "TimeConditionMet" : "PriceConditionMet";
        performData = abi.encode(tempCurrentPrice, reason);

        return (upkeepNeeded, performData);
    }

    /**
     * @notice Executes the upkeep, updating the token price and the last update timestamp.
     * @dev Decodes the `performData` to update `s_lastTokenPriceInUsd` and `s_lastTokenPriceUpdateTime`. It also emits a `PriceUpdated` event with the new price and the reason for the update.
     * @param performData Encoded data containing the new token price and the reason for the update. Should be decoded into a `uint256` for the price and a `string` for the reason.
     */
    function performUpkeep(bytes calldata performData) external {
        (uint256 currentPrice, string memory reason) = abi.decode(performData, (uint256, string));
        s_lastTokenPriceInUsd = currentPrice;
        s_lastTokenPriceUpdateTime = block.timestamp;

        emit PriceUpdated(currentPrice, block.timestamp, reason);
    }

    /**
     * @notice Buys MimicTokens with USDC at the current token price, allowing users to convert their USDC to MimicTokens.
     * @dev Performs a series of checks and operations to safely exchange USDC for MimicTokens:
     *      1. Verifies the caller's USDC allowance is sufficient for the transaction.
     *      2. Calculates the amount of MimicTokens that can be bought with the specified USDC amount at the current token price.
     *      3. Ensures the contract has enough MimicTokens to fulfill the transaction.
     *      4. Transfers USDC from the caller to the contract.
     *      5. Transfers the calculated amount of MimicTokens from the contract to the caller.
     *      Utilizes SafeERC20 for USDC transfers to prevent reentrancy attacks.
     * @param usdcAmount The amount of USDC the caller wishes to exchange for MimicTokens. The function expects this amount to have the correct decimal precision as per the USDC token standard (6 decimals).
     * @custom:error MimicTokenFeeds__InsufficientUSDCAllowance Thrown if the caller has not allowed the contract to spend enough USDC on their behalf.
     * @custom:error MimicTokenFeeds__InsufficientTokensInContract Thrown if the contract does not hold enough MimicTokens to complete the purchase.
     */
    function buyMimicTokenWithUSDC(uint256 usdcAmount) external nonReentrant {
        uint256 currentAllowance = s_usdc.allowance(msg.sender, address(this));
        if (currentAllowance < usdcAmount) {
            revert MimicTokenFeeds__InsufficientUsdcAllowance({
                currentAllowance: currentAllowance,
                requiredAllowance: usdcAmount
            });
        }

        uint256 currentMimicTokenPrice = PriceConverter.getPrice(s_priceFeed); // 18 dec
        uint256 mimicTokenAmount = calculateMimicTokenAmount(usdcAmount, currentMimicTokenPrice);

        if (balanceOf(address(this)) < mimicTokenAmount) {
            revert MimicTokenFeeds__InsufficientTokensInContract(mimicTokenAmount, balanceOf(address(this)));
        }

        s_usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        _transfer(address(this), msg.sender, mimicTokenAmount);
    }

    /**
     * @notice Sells MimicTokens in exchange for USDC at the current token price, allowing users to convert their MimicTokens back to USDC.
     * @dev Executes the sale of MimicTokens for USDC through a series of steps:
     *      1. Calculates the equivalent amount of USDC for the given MimicTokens based on the current token price.
     *      2. Checks if the contract has enough USDC to complete the purchase.
     *      3. Transfers the specified amount of MimicTokens from the caller to the contract.
     *      4. Transfers the calculated amount of USDC from the contract to the caller.
     *      Utilizes SafeERC20 for the transfer of USDC to mitigate reentrancy risks.
     *      Reverts if the contract's USDC balance is insufficient to fulfill the request.
     * @param mimicTokenAmount The amount of MimicTokens the caller wishes to sell. This amount should consider the token's decimal precision (18).
     * @custom:error MimicTokenFeeds__ZeroMimicTokenAmount Thrown if the token amount to sell is zero.
     * @custom:error MimicTokenFeeds__InsufficientUSDCInContract Thrown if the contract's balance of USDC is insufficient to pay the caller for the MimicTokens being sold.
     */
    function sellMimicTokenForUSDC(uint256 mimicTokenAmount) external nonReentrant returns (uint256) {
        if (mimicTokenAmount <= 0) {
            revert MimicTokenFeeds__ZeroMimicTokenAmount();
        }
        uint256 mimicTokenPrice = PriceConverter.getPrice(s_priceFeed);
        uint256 usdcAmount = calculateUSDCAmount(mimicTokenAmount, mimicTokenPrice);
        uint256 usdcBalance = s_usdc.balanceOf(address(this));

        if (usdcBalance < usdcAmount) {
            revert MimicTokenFeeds__InsufficientUSDCInContract(usdcAmount, usdcBalance);
        }

        _transfer(msg.sender, address(this), mimicTokenAmount);
        s_usdc.safeTransfer(msg.sender, usdcAmount);

        return usdcAmount;
    }

    /**
     * @dev Given a USDC amount and a MimicToken price, calculates the equivalent amount of MimicTokens.
     * The calculation adjusts for decimal differences between USDC (6 decimals) and MimicTokens (18 decimals).
     * @param usdcAmount Amount of USDC to convert to MimicTokens, with USDC's 6 decimal places considered.
     * @param mimicTokenPrice Current price of one MimicToken in USDC, scaled to 18 decimal places for precision.
     * @return The calculated amount of MimicTokens that can be bought with the specified USDC amount, scaled to 18 decimal places.
     * @custom:error MimicTokenFeeds__ZeroMimicTokenPrice Triggered if the MimicToken price is provided as zero.
     */
    function calculateMimicTokenAmount(uint256 usdcAmount, uint256 mimicTokenPrice) private pure returns (uint256) {
        if (mimicTokenPrice == 0) {
            revert MimicTokenFeeds__ZeroMimicTokenPrice();
        }

        uint256 mimicTokenAmount = (usdcAmount * USDC_6_TO_18_DECIMALS * DECIMALS_MULTIPLIER) / mimicTokenPrice;

        return mimicTokenAmount;
    }

    /**
     * @dev Calculates the amount of USDC to give for a given amount of MimicTokens being sold.
     * @param mimicTokenAmount The amount of MimicTokens being sold.
     * @param mimicTokenPrice The current price of MimicToken in USD.
     * @return The amount of USDC to transfer to the seller.
     */
    function calculateUSDCAmount(uint256 mimicTokenAmount, uint256 mimicTokenPrice) private pure returns (uint256) {
        // Calculate the amount of USDC to transfer.
        uint256 usdcAmount = ((mimicTokenAmount * mimicTokenPrice) / DECIMALS_MULTIPLIER) / USDC_6_TO_18_DECIMALS;
        return usdcAmount; // 6 decimals
    }

    /**
     * @notice Approves a spender to use a specified amount of LINK tokens held by this contract.
     * @dev Calls the `approve` function on the LINK token contract to set an allowance for the spender.
     * @param spender The address which will be approved to spend the LINK tokens.
     * @param amount The amount of LINK tokens the spender is approved to spend.
     * @return A boolean value indicating whether the approval was successful.
     */
    function approveLinkTokenSpending(address spender, uint256 amount) external onlyOwner returns (bool) {
        return i_link.approve(spender, amount);
    }

    /**
     * @notice Withdraws all LINK tokens held by the contract and sends them to the contract owner.
     * @dev Transfers the total balance of LINK tokens to the owner's address.
     * @custom:error MimicTokenFeeds__NoLinkBalanceToWithdraw Thrown if there are no LINK tokens in the contract to withdraw.
     * @custom:error MimicTokenFeeds__LinkTransferFailed Thrown if the transfer of LINK tokens to the owner fails.
     */
    function withdrawLink() external onlyOwner {
        uint256 linkBalance = i_link.balanceOf(address(this));

        if (linkBalance == 0) {
            revert MimicTokenFeeds__NoLinkBalanceToWithdraw();
        }

        bool transferSuccess = i_link.transfer(owner(), linkBalance);
        if (!transferSuccess) {
            revert MimicTokenFeeds__LinkTransferFailed();
        }
    }

    /**
     * @notice Withdraws all USDC tokens held by the contract and sends them to the contract owner.
     * @dev Transfers the total balance of USDC tokens to the owner's address.
     * @custom:error MimicTokenFeeds__NoUsdcBalanceToWithdraw Thrown if there are no USDC tokens in the contract to withdraw.
     */
    function withdrawUsdc() external onlyOwner {
        uint256 usdcBalance = s_usdc.balanceOf(address(this));

        if (usdcBalance == 0) {
            revert MimicTokenFeeds__NoUsdcBalanceToWithdraw();
        }

        s_usdc.safeTransfer(owner(), usdcBalance);
    }

    /// @dev Calculates the absolute difference between two unsigned integers.
    function absDiff(uint256 a, uint256 b) private pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

    function getInitialUpkeepFundingAmount() public pure returns (uint96) {
        return INIT_UPKEEP_FUNDING_AMOUNT;
    }

    function getPercentageMultiplier() public pure returns (uint256) {
        return PERCENTAGE_MULTIPLIER;
    }

    function getMinUpdateInterval() public pure returns (uint256) {
        return MIN_UPDATE_INTERVAL;
    }

    function getMinPriceDeviationBps() public pure returns (uint256) {
        return MIN_PRICE_DEVIATION_BPS;
    }

    function getPriceFeed() public view returns (AggregatorV3Interface) {
        return s_priceFeed;
    }

    function getLinkToken() public view returns (LinkTokenInterface) {
        return i_link;
    }

    function getAutomationRegistrar() public view returns (AutomationRegistrarInterface) {
        return i_registrar;
    }

    function getLastTokenPriceUpdateTime() public view returns (uint256) {
        return s_lastTokenPriceUpdateTime;
    }

    function getLastTokenPriceInUsd() public view returns (uint256) {
        return s_lastTokenPriceInUsd;
    }

    function getUpkeepID() public view returns (uint256) {
        return s_upkeepID;
    }
}
