// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/ITreasuryPriceOracle.sol";

/**
 * @title TreasuryPriceOracle
 * @notice Mock price oracle for treasury tokens
 * @dev In production, this would integrate with off-chain data providers
 */
contract TreasuryPriceOracle is ITreasuryPriceOracle, AccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    /// @dev NAV per token for each treasury token (scaled by 1e18)
    mapping(address => uint256) public navs;

    /// @dev Yield rates for each token (in basis points)
    mapping(address => uint256) public yieldRates;

    /// @dev Events
    event NAVUpdated(address indexed token, uint256 oldNAV, uint256 newNAV);
    event YieldRateUpdated(address indexed token, uint256 oldRate, uint256 newRate);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
    }

    /**
     * @notice Returns the current NAV per token
     */
    function getNAV(address token) external view override returns (uint256) {
        return navs[token];
    }

    /**
     * @notice Updates the NAV for a token
     */
    function setNAV(address token, uint256 nav) external override onlyRole(ORACLE_ROLE) {
        require(nav > 0, "TreasuryPriceOracle: invalid NAV");
        uint256 oldNAV = navs[token];
        navs[token] = nav;
        emit NAVUpdated(token, oldNAV, nav);
    }

    /**
     * @notice Returns the yield rate for a token
     */
    function getYieldRate(address token) external view override returns (uint256) {
        return yieldRates[token];
    }

    /**
     * @notice Updates the yield rate for a token
     */
    function setYieldRate(address token, uint256 yieldRate) external override onlyRole(ORACLE_ROLE) {
        require(yieldRate <= 10000, "TreasuryPriceOracle: yield rate too high");
        uint256 oldRate = yieldRates[token];
        yieldRates[token] = yieldRate;
        emit YieldRateUpdated(token, oldRate, yieldRate);
    }
}
