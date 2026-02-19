// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasuryPriceOracle
 * @notice Interface for treasury price oracles
 */
interface ITreasuryPriceOracle {
    /**
     * @notice Returns the current NAV (Net Asset Value) per token
     * @param token The treasury token address
     * @return The NAV per token (scaled by 1e18)
     */
    function getNAV(address token) external view returns (uint256);

    /**
     * @notice Updates the NAV for a token
     * @param token The treasury token address
     * @param nav The new NAV per token
     */
    function setNAV(address token, uint256 nav) external;

    /**
     * @notice Returns the yield rate for a token
     * @param token The treasury token address
     * @return The yield rate in basis points
     */
    function getYieldRate(address token) external view returns (uint256);

    /**
     * @notice Updates the yield rate for a token
     * @param token The treasury token address
     * @param yieldRate The new yield rate in basis points
     */
    function setYieldRate(address token, uint256 yieldRate) external;
}
