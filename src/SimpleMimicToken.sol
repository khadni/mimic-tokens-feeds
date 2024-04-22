// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {TokenPricingUtils} from "./TokenPricingUtils.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract SimpleMimicToken is ERC20, ReentrancyGuard, Ownable {
    error MimicTokenFeeds__NoUsdcBalanceToWithdraw();
    error MimicTokenFeeds__InsufficientUsdcAllowance(uint256 currentAllowance, uint256 requiredAllowance);
    error MimicTokenFeeds__InsufficientTokensInContract(uint256 requested, uint256 available);
    error MimicTokenFeeds__InsufficientUSDCInContract(uint256 requested, uint256 available);
    error MimicTokenFeeds__ZeroMimicTokenAmount();

    using TokenPricingUtils for uint256;
    using SafeERC20 for IERC20;

    IERC20 private immutable i_usdc;
    AggregatorV3Interface private s_priceFeed;

    uint256 private constant DECIMALS_MULTIPLIER = 1e18; // Multiplier to adjust for decimal places
    uint256 private constant USDC_6_TO_18_DECIMALS = 1e12; // Multiplier to adjust USDC from 6 to 18 decimals

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address usdcAddress,
        address priceFeedAddress
    ) ERC20(name, symbol) Ownable() {
        _mint(address(this), initialSupply);
        i_usdc = IERC20(usdcAddress);
        s_priceFeed = AggregatorV3Interface(priceFeedAddress);
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
    function buyMimicTokenWithUSDCAmount(uint256 usdcAmount) external nonReentrant {
        uint256 currentAllowance = i_usdc.allowance(msg.sender, address(this));
        if (currentAllowance < usdcAmount) {
            revert MimicTokenFeeds__InsufficientUsdcAllowance({
                currentAllowance: currentAllowance,
                requiredAllowance: usdcAmount
            });
        }

        uint256 currentMimicTokenPrice = TokenPricingUtils.getPrice(s_priceFeed); // 18 dec
        uint256 mimicTokenAmount = TokenPricingUtils.calculateMimicTokenAmount(usdcAmount, currentMimicTokenPrice);

        if (balanceOf(address(this)) < mimicTokenAmount) {
            revert MimicTokenFeeds__InsufficientTokensInContract(mimicTokenAmount, balanceOf(address(this)));
        }

        i_usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        _transfer(address(this), msg.sender, mimicTokenAmount);
    }

    /**
     * @notice Buys a specified amount of MimicTokens using USDC based on the current token price.
     * @dev Performs a series of checks and operations to safely exchange USDC for the specified amount of MimicTokens:
     *      1. Fetches the current MimicToken price.
     *      2. Calculates the required USDC amount to buy the specified number of MimicTokens.
     *      3. Verifies the caller's USDC allowance is sufficient for the transaction.
     *      4. Ensures the contract has enough USDC to fulfill the transaction.
     *      5. Transfers the calculated amount of USDC from the caller to the contract.
     *      6. Transfers the specified amount of MimicTokens from the contract to the caller.
     *      Utilizes SafeERC20 for USDC transfers to prevent reentrancy attacks.
     * @param mimicTokenCount The number of MimicTokens the caller wishes to purchase. This amount should consider the token's decimal precision (18).
     * @custom:error MimicTokenFeeds__InsufficientUSDCAllowance Thrown if the caller has not allowed the contract to spend enough USDC on their behalf.
     * @custom:error MimicTokenFeeds__InsufficientTokensInContract Thrown if the contract does not hold enough MimicTokens to complete the purchase.
     * @custom:error MimicTokenFeeds__InsufficientUSDCInContract Thrown if the contract's balance of USDC is insufficient to pay for the MimicTokens.
     */
    function buyMimicTokenWithTokenAmount(uint256 mimicTokenCount) external nonReentrant {
        if (mimicTokenCount <= 0) {
            revert MimicTokenFeeds__ZeroMimicTokenAmount();
        }

        uint256 currentMimicTokenPrice = TokenPricingUtils.getPrice(s_priceFeed);
        uint256 requiredUsdcAmount = TokenPricingUtils.calculateUSDCAmount(mimicTokenCount, currentMimicTokenPrice);
        uint256 currentAllowance = i_usdc.allowance(msg.sender, address(this));

        if (currentAllowance < requiredUsdcAmount) {
            revert MimicTokenFeeds__InsufficientUsdcAllowance({
                currentAllowance: currentAllowance,
                requiredAllowance: requiredUsdcAmount
            });
        }

        if (balanceOf(address(this)) < mimicTokenCount) {
            revert MimicTokenFeeds__InsufficientTokensInContract(mimicTokenCount, balanceOf(address(this)));
        }

        i_usdc.safeTransferFrom(msg.sender, address(this), requiredUsdcAmount);
        _transfer(address(this), msg.sender, mimicTokenCount);
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
        uint256 mimicTokenPrice = TokenPricingUtils.getPrice(s_priceFeed);
        uint256 usdcAmount = TokenPricingUtils.calculateUSDCAmount(mimicTokenAmount, mimicTokenPrice);
        uint256 usdcBalance = i_usdc.balanceOf(address(this));

        if (usdcBalance < usdcAmount) {
            revert MimicTokenFeeds__InsufficientUSDCInContract(usdcAmount, usdcBalance);
        }

        _transfer(msg.sender, address(this), mimicTokenAmount);
        i_usdc.safeTransfer(msg.sender, usdcAmount);

        return usdcAmount;
    }

    /**
     * @notice Withdraws all USDC tokens held by the contract and sends them to the contract owner.
     * @dev Transfers the total balance of USDC tokens to the owner's address.
     * @custom:error MimicTokenFeeds__NoUsdcBalanceToWithdraw Thrown if there are no USDC tokens in the contract to withdraw.
     */
    function withdrawUsdc() external onlyOwner {
        uint256 usdcBalance = i_usdc.balanceOf(address(this));

        if (usdcBalance == 0) {
            revert MimicTokenFeeds__NoUsdcBalanceToWithdraw();
        }

        i_usdc.safeTransfer(owner(), usdcBalance);
    }

    function getPriceFeed() public view returns (AggregatorV3Interface) {
        return s_priceFeed;
    }
}
