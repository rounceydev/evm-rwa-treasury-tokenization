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
 * @title RebasingTreasuryToken
 * @notice Rebasing variant where balances increase daily to reflect yield
 * @dev Inspired by Ondo Finance's rOUSG - price stays ~$1, balances rebase
 */
contract RebasingTreasuryToken is
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

    /// @dev Current yield rate (APY in basis points)
    uint256 public yieldRate;

    /// @dev Last rebase timestamp
    uint256 public lastRebase;

    /// @dev Rebase interval (e.g., 1 day)
    uint256 public rebaseInterval;

    /// @dev Rebase index (scaled by 1e18)
    uint256 public rebaseIndex;

    /// @dev Minimum mint amount
    uint256 public minMintAmount;

    /// @dev Minimum redeem amount
    uint256 public minRedeemAmount;

    /// @dev Whitelist mapping
    mapping(address => bool) public whitelist;

    /// @dev Blacklist mapping
    mapping(address => bool) public blacklist;

    /// @dev Whether whitelist is enforced
    bool public whitelistEnabled;

    /// @dev Scaled balances (internal accounting)
    mapping(address => uint256) private _scaledBalances;

    /// @dev Total scaled supply
    uint256 private _scaledTotalSupply;

    /// @dev Events
    event Mint(address indexed to, uint256 amount);
    event Redeem(address indexed from, uint256 amount);
    event Rebase(uint256 oldIndex, uint256 newIndex, uint256 timestamp);
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);
    event WhitelistUpdated(address indexed account, bool whitelisted);
    event BlacklistUpdated(address indexed account, bool blacklisted);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
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

        require(_underlyingAsset != address(0), "RebasingTreasuryToken: invalid underlying");
        require(_priceOracle != address(0), "RebasingTreasuryToken: invalid oracle");
        require(admin != address(0), "RebasingTreasuryToken: invalid admin");

        underlyingAsset = _underlyingAsset;
        priceOracle = ITreasuryPriceOracle(_priceOracle);
        yieldRate = _yieldRate;
        minMintAmount = _minMintAmount;
        minRedeemAmount = _minRedeemAmount;
        rebaseInterval = 1 days;
        lastRebase = block.timestamp;
        rebaseIndex = 1e18; // Start at 1.0
        whitelistEnabled = true;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(REDEEMER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        priceOracle.setNAV(address(this), 1e18); // Price stays at $1
        priceOracle.setYieldRate(address(this), _yieldRate);
    }

    /**
     * @notice Mints tokens
     */
    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(to != address(0), "RebasingTreasuryToken: invalid recipient");
        require(amount >= minMintAmount, "RebasingTreasuryToken: amount below minimum");
        require(!blacklist[to], "RebasingTreasuryToken: recipient blacklisted");
        if (whitelistEnabled) {
            require(whitelist[to], "RebasingTreasuryToken: recipient not whitelisted");
        }

        _rebaseIfNeeded();

        uint256 scaledAmount = (amount * 1e18) / rebaseIndex;
        _scaledBalances[to] += scaledAmount;
        _scaledTotalSupply += scaledAmount;

        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Redeems tokens
     */
    function redeem(address from, uint256 amount) external override onlyRole(REDEEMER_ROLE) whenNotPaused nonReentrant {
        require(from != address(0), "RebasingTreasuryToken: invalid sender");
        require(amount >= minRedeemAmount, "RebasingTreasuryToken: amount below minimum");
        require(balanceOf(from) >= amount, "RebasingTreasuryToken: insufficient balance");

        _rebaseIfNeeded();

        uint256 scaledAmount = (amount * 1e18) / rebaseIndex;
        _scaledBalances[from] -= scaledAmount;
        _scaledTotalSupply -= scaledAmount;

        emit Redeem(from, amount);
        emit Transfer(from, address(0), amount);
    }

    /**
     * @notice Returns the current price per token (always ~$1 for rebasing)
     */
    function getPricePerToken() public view override returns (uint256) {
        return priceOracle.getNAV(address(this));
    }

    /**
     * @notice Returns the underlying asset address
     */
    function getUnderlyingAsset() external view override returns (address) {
        return underlyingAsset;
    }

    /**
     * @notice Returns the current yield rate
     */
    function getYieldRate() external view override returns (uint256) {
        return yieldRate;
    }

    /**
     * @notice Updates the yield rate
     */
    function setYieldRate(uint256 newYieldRate) external override onlyRole(ORACLE_ROLE) {
        require(newYieldRate <= 10000, "RebasingTreasuryToken: yield rate too high");
        uint256 oldRate = yieldRate;
        yieldRate = newYieldRate;
        priceOracle.setYieldRate(address(this), newYieldRate);
        emit YieldRateUpdated(oldRate, newYieldRate);
    }

    /**
     * @notice Performs rebase if interval has passed
     */
    function rebase() external onlyRole(ORACLE_ROLE) {
        _rebaseIfNeeded();
    }

    /**
     * @notice Internal rebase function
     */
    function _rebaseIfNeeded() internal {
        if (block.timestamp >= lastRebase + rebaseInterval) {
            uint256 timeElapsed = block.timestamp - lastRebase;
            uint256 periods = timeElapsed / rebaseInterval;
            
            // Calculate rebase: index increases by yieldRate per year
            // Daily rebase: index *= (1 + yieldRate / (10000 * 365))
            uint256 rebaseMultiplier = 1e18 + (yieldRate * rebaseInterval) / (10000 * 365 days);
            
            uint256 oldIndex = rebaseIndex;
            for (uint256 i = 0; i < periods && i < 365; i++) {
                rebaseIndex = (rebaseIndex * rebaseMultiplier) / 1e18;
            }
            
            lastRebase = block.timestamp;
            emit Rebase(oldIndex, rebaseIndex, block.timestamp);
        }
    }

    /**
     * @notice Returns balance accounting for rebase
     */
    function balanceOf(address account) public view override returns (uint256) {
        uint256 currentIndex = _getCurrentIndex();
        return (_scaledBalances[account] * currentIndex) / 1e18;
    }

    /**
     * @notice Returns total supply accounting for rebase
     */
    function totalSupply() public view override returns (uint256) {
        uint256 currentIndex = _getCurrentIndex();
        return (_scaledTotalSupply * currentIndex) / 1e18;
    }

    /**
     * @notice Gets current rebase index (with pending rebase)
     */
    function _getCurrentIndex() internal view returns (uint256) {
        if (block.timestamp < lastRebase + rebaseInterval) {
            return rebaseIndex;
        }
        
        uint256 timeElapsed = block.timestamp - lastRebase;
        uint256 periods = timeElapsed / rebaseInterval;
        uint256 rebaseMultiplier = 1e18 + (yieldRate * rebaseInterval) / (10000 * 365 days);
        
        uint256 currentIndex = rebaseIndex;
        for (uint256 i = 0; i < periods && i < 365; i++) {
            currentIndex = (currentIndex * rebaseMultiplier) / 1e18;
        }
        
        return currentIndex;
    }

    /**
     * @notice Checks if an address is whitelisted
     */
    function isWhitelisted(address account) external view override returns (bool) {
        return whitelist[account];
    }

    /**
     * @notice Adds to whitelist
     */
    function addToWhitelist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "RebasingTreasuryToken: invalid address");
        whitelist[account] = true;
        emit WhitelistUpdated(account, true);
    }

    /**
     * @notice Removes from whitelist
     */
    function removeFromWhitelist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelist[account] = false;
        emit WhitelistUpdated(account, false);
    }

    /**
     * @notice Adds to blacklist
     */
    function addToBlacklist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "RebasingTreasuryToken: invalid address");
        blacklist[account] = true;
        emit BlacklistUpdated(account, true);
    }

    /**
     * @notice Removes from blacklist
     */
    function removeFromBlacklist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blacklist[account] = false;
        emit BlacklistUpdated(account, false);
    }

    /**
     * @notice Sets whitelist enabled
     */
    function setWhitelistEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistEnabled = enabled;
    }

    /**
     * @notice Pauses all operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Hook called before token transfer
     */
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        _rebaseIfNeeded();
        
        if (from != address(0) && to != address(0)) {
            require(!blacklist[from], "RebasingTreasuryToken: sender blacklisted");
            require(!blacklist[to], "RebasingTreasuryToken: recipient blacklisted");
            if (whitelistEnabled) {
                require(whitelist[from] || from == address(this), "RebasingTreasuryToken: sender not whitelisted");
                require(whitelist[to] || to == address(this), "RebasingTreasuryToken: recipient not whitelisted");
            }
        }

        if (from != address(0)) {
            uint256 scaledAmount = (value * 1e18) / rebaseIndex;
            _scaledBalances[from] -= scaledAmount;
        }
        if (to != address(0)) {
            uint256 scaledAmount = (value * 1e18) / rebaseIndex;
            _scaledBalances[to] += scaledAmount;
        }

        super._update(from, to, value);
    }

    /**
     * @notice Authorizes upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
