// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITreasuryToken.sol";
import "../interfaces/ITreasuryPriceOracle.sol";

/**
 * @title TreasuryToken
 * @notice Yield-bearing ERC-20 token representing tokenized US Treasury assets
 * @dev Inspired by Ondo Finance's OUSG - appreciating token where value increases over time
 * The token balance stays fixed but the price/NAV increases to reflect yield accrual
 */
contract TreasuryToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ITreasuryToken
{
    /// @dev Role identifiers
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev The underlying asset (e.g., USDC)
    address public underlyingAsset;

    /// @dev Price oracle contract
    ITreasuryPriceOracle public priceOracle;

    /// @dev Current yield rate (APY in basis points, e.g., 400 = 4%)
    uint256 public yieldRate;

    /// @dev Last yield update timestamp
    uint256 public lastYieldUpdate;

    /// @dev Minimum mint amount
    uint256 public minMintAmount;

    /// @dev Minimum redeem amount
    uint256 public minRedeemAmount;

    /// @dev Whitelist mapping for compliance
    mapping(address => bool) public whitelist;

    /// @dev Blacklist mapping for compliance
    mapping(address => bool) public blacklist;

    /// @dev Whether whitelist is enforced
    bool public whitelistEnabled;

    /// @dev Initial price per token (1:1 with underlying)
    uint256 public constant INITIAL_PRICE = 1e18;

    /// @dev Events
    event Mint(address indexed to, uint256 amount, uint256 pricePerToken);
    event Redeem(address indexed from, uint256 amount, uint256 pricePerToken);
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);
    event WhitelistUpdated(address indexed account, bool whitelisted);
    event BlacklistUpdated(address indexed account, bool blacklisted);
    event WhitelistToggled(bool enabled);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param name Token name
     * @param symbol Token symbol
     * @param _underlyingAsset Address of underlying asset (e.g., USDC)
     * @param _priceOracle Address of price oracle
     * @param _yieldRate Initial yield rate in basis points
     * @param _minMintAmount Minimum mint amount
     * @param _minRedeemAmount Minimum redeem amount
     * @param admin Address to grant admin role
     */
    function initialize(
        string memory name,
        string memory symbol,
        address _underlyingAsset,
        address _priceOracle,
        uint256 _yieldRate,
        uint256 _minMintAmount,
        uint256 _minRedeemAmount,
        address admin
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        require(_underlyingAsset != address(0), "TreasuryToken: invalid underlying");
        require(_priceOracle != address(0), "TreasuryToken: invalid oracle");
        require(admin != address(0), "TreasuryToken: invalid admin");

        underlyingAsset = _underlyingAsset;
        priceOracle = ITreasuryPriceOracle(_priceOracle);
        yieldRate = _yieldRate;
        minMintAmount = _minMintAmount;
        minRedeemAmount = _minRedeemAmount;
        lastYieldUpdate = block.timestamp;
        whitelistEnabled = true;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(REDEEMER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Initialize oracle with initial price
        priceOracle.setNAV(address(this), INITIAL_PRICE);
        priceOracle.setYieldRate(address(this), _yieldRate);
    }

    /**
     * @notice Mints tokens when off-chain assets are deposited
     * @param to The address to receive the tokens
     * @param amount The amount of tokens to mint (in underlying units)
     */
    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(to != address(0), "TreasuryToken: invalid recipient");
        require(amount >= minMintAmount, "TreasuryToken: amount below minimum");
        require(!blacklist[to], "TreasuryToken: recipient blacklisted");
        if (whitelistEnabled) {
            require(whitelist[to], "TreasuryToken: recipient not whitelisted");
        }

        uint256 pricePerToken = getPricePerToken();
        uint256 tokensToMint = (amount * 1e18) / pricePerToken;

        _mint(to, tokensToMint);

        emit Mint(to, tokensToMint, pricePerToken);
    }

    /**
     * @notice Redeems tokens and signals off-chain payout
     * @param from The address redeeming tokens
     * @param amount The amount of tokens to redeem
     */
    function redeem(address from, uint256 amount) external override onlyRole(REDEEMER_ROLE) whenNotPaused nonReentrant {
        require(from != address(0), "TreasuryToken: invalid sender");
        require(amount >= minRedeemAmount, "TreasuryToken: amount below minimum");
        require(balanceOf(from) >= amount, "TreasuryToken: insufficient balance");

        uint256 pricePerToken = getPricePerToken();
        uint256 underlyingAmount = (amount * pricePerToken) / 1e18;

        _burn(from, amount);

        emit Redeem(from, amount, pricePerToken);
    }

    /**
     * @notice Returns the current price/NAV per token
     * @return The price per token (scaled by 1e18)
     */
    function getPricePerToken() public view override returns (uint256) {
        return priceOracle.getNAV(address(this));
    }

    /**
     * @notice Returns the underlying asset address
     * @return The address of the underlying asset
     */
    function getUnderlyingAsset() external view override returns (address) {
        return underlyingAsset;
    }

    /**
     * @notice Returns the current yield rate (APY in basis points)
     * @return The yield rate in basis points
     */
    function getYieldRate() external view override returns (uint256) {
        return yieldRate;
    }

    /**
     * @notice Updates the yield rate
     * @param newYieldRate The new yield rate in basis points
     */
    function setYieldRate(uint256 newYieldRate) external override onlyRole(ORACLE_ROLE) {
        require(newYieldRate <= 10000, "TreasuryToken: yield rate too high"); // Max 100%
        uint256 oldRate = yieldRate;
        yieldRate = newYieldRate;
        lastYieldUpdate = block.timestamp;

        priceOracle.setYieldRate(address(this), newYieldRate);

        emit YieldRateUpdated(oldRate, newYieldRate);
    }

    /**
     * @notice Updates the price/NAV via oracle
     * @dev This simulates yield accrual - price increases over time
     */
    function updatePrice() external onlyRole(ORACLE_ROLE) {
        uint256 currentPrice = priceOracle.getNAV(address(this));
        uint256 timeElapsed = block.timestamp - lastYieldUpdate;
        
        // Calculate yield accrued: price * (1 + yieldRate * timeElapsed / 365 days)
        // Simplified: price increases by yieldRate per year
        uint256 yieldAccrued = (currentPrice * yieldRate * timeElapsed) / (10000 * 365 days);
        uint256 newPrice = currentPrice + yieldAccrued;
        
        priceOracle.setNAV(address(this), newPrice);
        lastYieldUpdate = block.timestamp;
    }

    /**
     * @notice Checks if an address is whitelisted
     * @param account The address to check
     * @return True if whitelisted
     */
    function isWhitelisted(address account) external view override returns (bool) {
        return whitelist[account];
    }

    /**
     * @notice Adds an address to the whitelist
     * @param account The address to whitelist
     */
    function addToWhitelist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "TreasuryToken: invalid address");
        whitelist[account] = true;
        emit WhitelistUpdated(account, true);
    }

    /**
     * @notice Removes an address from the whitelist
     * @param account The address to remove
     */
    function removeFromWhitelist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelist[account] = false;
        emit WhitelistUpdated(account, false);
    }

    /**
     * @notice Adds an address to the blacklist
     * @param account The address to blacklist
     */
    function addToBlacklist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "TreasuryToken: invalid address");
        blacklist[account] = true;
        emit BlacklistUpdated(account, true);
    }

    /**
     * @notice Removes an address from the blacklist
     * @param account The address to remove
     */
    function removeFromBlacklist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blacklist[account] = false;
        emit BlacklistUpdated(account, false);
    }

    /**
     * @notice Toggles whitelist enforcement
     * @param enabled Whether to enforce whitelist
     */
    function setWhitelistEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistEnabled = enabled;
        emit WhitelistToggled(enabled);
    }

    /**
     * @notice Updates the price oracle
     * @param newOracle The new oracle address
     */
    function setPriceOracle(address newOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newOracle != address(0), "TreasuryToken: invalid oracle");
        address oldOracle = address(priceOracle);
        priceOracle = ITreasuryPriceOracle(newOracle);
        emit PriceOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Pauses all token operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all token operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Hook called before token transfer
     * @dev Enforces whitelist and blacklist restrictions
     */
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        if (from != address(0) && to != address(0)) {
            // Transfer between non-zero addresses
            require(!blacklist[from], "TreasuryToken: sender blacklisted");
            require(!blacklist[to], "TreasuryToken: recipient blacklisted");
            if (whitelistEnabled) {
                require(whitelist[from] || from == address(this), "TreasuryToken: sender not whitelisted");
                require(whitelist[to] || to == address(this), "TreasuryToken: recipient not whitelisted");
            }
        }
        super._update(from, to, value);
    }

    /**
     * @notice Authorizes upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
