// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasuryToken
 * @notice Interface for treasury tokenization contracts
 */
interface ITreasuryToken {
    /**
     * @notice Mints tokens when off-chain assets are deposited
     * @param to The address to receive the tokens
     * @param amount The amount of tokens to mint (in underlying units)
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Redeems tokens and signals off-chain payout
     * @param from The address redeeming tokens
     * @param amount The amount of tokens to redeem
     */
    function redeem(address from, uint256 amount) external;

    /**
     * @notice Returns the current price/NAV per token
     * @return The price per token (scaled by 1e18)
     */
    function getPricePerToken() external view returns (uint256);

    /**
     * @notice Returns the underlying asset address
     * @return The address of the underlying asset (e.g., USDC)
     */
    function getUnderlyingAsset() external view returns (address);

    /**
     * @notice Returns the current yield rate (APY in basis points)
     * @return The yield rate in basis points
     */
    function getYieldRate() external view returns (uint256);

    /**
     * @notice Updates the yield rate
     * @param newYieldRate The new yield rate in basis points
     */
    function setYieldRate(uint256 newYieldRate) external;

    /**
     * @notice Checks if an address is whitelisted
     * @param account The address to check
     * @return True if whitelisted
     */
    function isWhitelisted(address account) external view returns (bool);
}
