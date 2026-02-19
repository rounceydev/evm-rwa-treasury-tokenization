const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

    // Deploy MockUSDC
    console.log("\n=== Deploying MockUSDC ===");
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();
    console.log("MockUSDC deployed to:", mockUSDC.target);

    // Deploy Price Oracle
    console.log("\n=== Deploying Price Oracle ===");
    const TreasuryPriceOracle = await ethers.getContractFactory("TreasuryPriceOracle");
    const priceOracle = await TreasuryPriceOracle.deploy(deployer.address);
    await priceOracle.waitForDeployment();
    console.log("TreasuryPriceOracle deployed to:", priceOracle.target);

    // Deploy TreasuryToken (UUPS Proxy)
    console.log("\n=== Deploying TreasuryToken (UUPS Proxy) ===");
    const TreasuryToken = await ethers.getContractFactory("TreasuryToken");
    const treasuryToken = await upgrades.deployProxy(
        TreasuryToken,
        [
            "Tokenized US Treasury",
            "OUSG",
            mockUSDC.target,
            priceOracle.target,
            400, // 4% APY in basis points
            ethers.parseUnits("1000", 6), // min mint: 1000 USDC
            ethers.parseUnits("1000", 6), // min redeem: 1000 USDC
            deployer.address,
        ],
        { initializer: "initialize" }
    );
    await treasuryToken.waitForDeployment();
    console.log("TreasuryToken (proxy) deployed to:", treasuryToken.target);

    // Get implementation address
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(
        treasuryToken.target
    );
    console.log("TreasuryToken (implementation) deployed to:", implementationAddress);

    // Deploy RebasingTreasuryToken (optional)
    console.log("\n=== Deploying RebasingTreasuryToken (UUPS Proxy) ===");
    const RebasingTreasuryToken = await ethers.getContractFactory("RebasingTreasuryToken");
    const rebasingToken = await upgrades.deployProxy(
        RebasingTreasuryToken,
        [
            "Rebasing Tokenized US Treasury",
            "rOUSG",
            mockUSDC.target,
            priceOracle.target,
            400, // 4% APY
            ethers.parseUnits("1000", 6),
            ethers.parseUnits("1000", 6),
            deployer.address,
        ],
        { initializer: "initialize" }
    );
    await rebasingToken.waitForDeployment();
    console.log("RebasingTreasuryToken (proxy) deployed to:", rebasingToken.target);

    const rebasingImplementationAddress = await upgrades.erc1967.getImplementationAddress(
        rebasingToken.target
    );
    console.log("RebasingTreasuryToken (implementation) deployed to:", rebasingImplementationAddress);

    // Whitelist deployer for testing
    console.log("\n=== Setting up roles and whitelist ===");
    await treasuryToken.addToWhitelist(deployer.address);
    await rebasingToken.addToWhitelist(deployer.address);
    console.log("Deployer whitelisted");

    // Grant ORACLE_ROLE to deployer for price updates
    const ORACLE_ROLE = await treasuryToken.ORACLE_ROLE();
    await treasuryToken.grantRole(ORACLE_ROLE, deployer.address);
    await rebasingToken.grantRole(ORACLE_ROLE, deployer.address);
    console.log("Oracle role granted to deployer");

    console.log("\n=== Deployment Summary ===");
    console.log("MockUSDC:", mockUSDC.target);
    console.log("TreasuryPriceOracle:", priceOracle.target);
    console.log("\nTreasuryToken (OUSG-style):");
    console.log("  Proxy:", treasuryToken.target);
    console.log("  Implementation:", implementationAddress);
    console.log("\nRebasingTreasuryToken (rOUSG-style):");
    console.log("  Proxy:", rebasingToken.target);
    console.log("  Implementation:", rebasingImplementationAddress);

    console.log("\n=== Next Steps ===");
    console.log("1. Whitelist addresses: treasuryToken.addToWhitelist(address)");
    console.log("2. Mint tokens: treasuryToken.mint(to, amount)");
    console.log("3. Update price (yield accrual): treasuryToken.updatePrice()");
    console.log("4. Redeem tokens: treasuryToken.redeem(from, amount)");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
