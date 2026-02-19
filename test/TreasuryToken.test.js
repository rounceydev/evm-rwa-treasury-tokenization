const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("TreasuryToken", function () {
    async function deployTreasuryTokenFixture() {
        const [owner, minter, redeemer, user1, user2, unauthorized] = await ethers.getSigners();

        // Deploy MockUSDC
        const MockUSDC = await ethers.getContractFactory("MockUSDC");
        const mockUSDC = await MockUSDC.deploy();
        await mockUSDC.waitForDeployment();

        // Deploy Price Oracle
        const TreasuryPriceOracle = await ethers.getContractFactory("TreasuryPriceOracle");
        const priceOracle = await TreasuryPriceOracle.deploy(owner.address);
        await priceOracle.waitForDeployment();

        // Deploy TreasuryToken implementation
        const TreasuryToken = await ethers.getContractFactory("TreasuryToken");
        const treasuryToken = await upgrades.deployProxy(
            TreasuryToken,
            [
                "Tokenized US Treasury",
                "OUSG",
                mockUSDC.target,
                priceOracle.target,
                400, // 4% APY
                ethers.parseUnits("1000", 6), // min mint
                ethers.parseUnits("1000", 6), // min redeem
                owner.address,
            ],
            { initializer: "initialize" }
        );
        await treasuryToken.waitForDeployment();

        // Grant roles
        const MINTER_ROLE = await treasuryToken.MINTER_ROLE();
        const REDEEMER_ROLE = await treasuryToken.REDEEMER_ROLE();
        await treasuryToken.grantRole(MINTER_ROLE, minter.address);
        await treasuryToken.grantRole(REDEEMER_ROLE, redeemer.address);

        // Whitelist users
        await treasuryToken.addToWhitelist(user1.address);
        await treasuryToken.addToWhitelist(user2.address);
        await treasuryToken.addToWhitelist(minter.address);
        await treasuryToken.addToWhitelist(redeemer.address);

        return {
            owner,
            minter,
            redeemer,
            user1,
            user2,
            unauthorized,
            mockUSDC,
            priceOracle,
            treasuryToken,
        };
    }

    describe("Deployment", function () {
        it("Should initialize correctly", async function () {
            const { treasuryToken, mockUSDC, priceOracle, owner } = await loadFixture(
                deployTreasuryTokenFixture
            );

            expect(await treasuryToken.name()).to.equal("Tokenized US Treasury");
            expect(await treasuryToken.symbol()).to.equal("OUSG");
            expect(await treasuryToken.getUnderlyingAsset()).to.equal(mockUSDC.target);
            expect(await treasuryToken.getPricePerToken()).to.equal(ethers.parseUnits("1", 18));
            expect(await treasuryToken.getYieldRate()).to.equal(400);
        });

        it("Should set correct roles", async function () {
            const { treasuryToken, owner, minter, redeemer } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const ADMIN_ROLE = await treasuryToken.DEFAULT_ADMIN_ROLE();
            const MINTER_ROLE = await treasuryToken.MINTER_ROLE();
            const REDEEMER_ROLE = await treasuryToken.REDEEMER_ROLE();

            expect(await treasuryToken.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
            expect(await treasuryToken.hasRole(MINTER_ROLE, minter.address)).to.be.true;
            expect(await treasuryToken.hasRole(REDEEMER_ROLE, redeemer.address)).to.be.true;
        });
    });

    describe("Minting", function () {
        it("Should allow minter to mint tokens", async function () {
            const { treasuryToken, minter, user1, mockUSDC } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6); // 10k USDC
            await treasuryToken.connect(minter).mint(user1.address, mintAmount);

            const balance = await treasuryToken.balanceOf(user1.address);
            expect(balance).to.be.gt(0);
        });

        it("Should revert if amount below minimum", async function () {
            const { treasuryToken, minter, user1 } = await loadFixture(deployTreasuryTokenFixture);

            const mintAmount = ethers.parseUnits("100", 6); // Below minimum
            await expect(
                treasuryToken.connect(minter).mint(user1.address, mintAmount)
            ).to.be.revertedWith("TreasuryToken: amount below minimum");
        });

        it("Should revert if recipient not whitelisted", async function () {
            const { treasuryToken, minter, unauthorized } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6);
            await expect(
                treasuryToken.connect(minter).mint(unauthorized.address, mintAmount)
            ).to.be.revertedWith("TreasuryToken: recipient not whitelisted");
        });

        it("Should revert if unauthorized user tries to mint", async function () {
            const { treasuryToken, user1, unauthorized } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6);
            await expect(
                treasuryToken.connect(unauthorized).mint(user1.address, mintAmount)
            ).to.be.reverted;
        });
    });

    describe("Redemption", function () {
        it("Should allow redeemer to redeem tokens", async function () {
            const { treasuryToken, minter, redeemer, user1 } = await loadFixture(
                deployTreasuryTokenFixture
            );

            // First mint
            const mintAmount = ethers.parseUnits("10000", 6);
            await treasuryToken.connect(minter).mint(user1.address, mintAmount);
            const balance = await treasuryToken.balanceOf(user1.address);

            // Then redeem
            const redeemAmount = balance / 2n;
            await treasuryToken.connect(redeemer).redeem(user1.address, redeemAmount);

            const newBalance = await treasuryToken.balanceOf(user1.address);
            expect(newBalance).to.equal(balance - redeemAmount);
        });

        it("Should revert if amount below minimum", async function () {
            const { treasuryToken, redeemer, user1 } = await loadFixture(
                deployTreasuryTokenFixture
            );

            await expect(
                treasuryToken.connect(redeemer).redeem(user1.address, ethers.parseUnits("100", 18))
            ).to.be.revertedWith("TreasuryToken: amount below minimum");
        });

        it("Should revert if insufficient balance", async function () {
            const { treasuryToken, redeemer, user1 } = await loadFixture(
                deployTreasuryTokenFixture
            );

            await expect(
                treasuryToken
                    .connect(redeemer)
                    .redeem(user1.address, ethers.parseUnits("1000000", 18))
            ).to.be.revertedWith("TreasuryToken: insufficient balance");
        });
    });

    describe("Yield Accrual", function () {
        it("Should update price when yield accrues", async function () {
            const { treasuryToken, owner, priceOracle } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const initialPrice = await treasuryToken.getPricePerToken();
            expect(initialPrice).to.equal(ethers.parseUnits("1", 18));

            // Fast forward time (simulate)
            await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]); // 1 year
            await ethers.provider.send("evm_mine", []);

            // Update price (simulates yield accrual)
            await treasuryToken.connect(owner).updatePrice();

            const newPrice = await treasuryToken.getPricePerToken();
            expect(newPrice).to.be.gt(initialPrice);
        });

        it("Should allow updating yield rate", async function () {
            const { treasuryToken, owner } = await loadFixture(deployTreasuryTokenFixture);

            const ORACLE_ROLE = await treasuryToken.ORACLE_ROLE();
            await treasuryToken.grantRole(ORACLE_ROLE, owner.address);

            await treasuryToken.connect(owner).setYieldRate(500); // 5%
            expect(await treasuryToken.getYieldRate()).to.equal(500);
        });
    });

    describe("Whitelist/Blacklist", function () {
        it("Should enforce whitelist on transfers", async function () {
            const { treasuryToken, minter, user1, user2, unauthorized } = await loadFixture(
                deployTreasuryTokenFixture
            );

            // Mint to user1
            const mintAmount = ethers.parseUnits("10000", 6);
            await treasuryToken.connect(minter).mint(user1.address, mintAmount);
            const balance = await treasuryToken.balanceOf(user1.address);

            // Try to transfer to unauthorized user
            await expect(
                treasuryToken.connect(user1).transfer(unauthorized.address, balance / 2n)
            ).to.be.revertedWith("TreasuryToken: recipient not whitelisted");
        });

        it("Should allow transfers between whitelisted users", async function () {
            const { treasuryToken, minter, user1, user2 } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6);
            await treasuryToken.connect(minter).mint(user1.address, mintAmount);
            const balance = await treasuryToken.balanceOf(user1.address);

            await treasuryToken.connect(user1).transfer(user2.address, balance / 2n);
            expect(await treasuryToken.balanceOf(user2.address)).to.be.gt(0);
        });

        it("Should prevent blacklisted users from transferring", async function () {
            const { treasuryToken, minter, user1, user2 } = await loadFixture(
                deployTreasuryTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6);
            await treasuryToken.connect(minter).mint(user1.address, mintAmount);
            const balance = await treasuryToken.balanceOf(user1.address);

            await treasuryToken.addToBlacklist(user1.address);

            await expect(
                treasuryToken.connect(user1).transfer(user2.address, balance / 2n)
            ).to.be.revertedWith("TreasuryToken: sender blacklisted");
        });

        it("Should allow disabling whitelist", async function () {
            const { treasuryToken, owner, minter, user1, unauthorized } = await loadFixture(
                deployTreasuryTokenFixture
            );

            await treasuryToken.connect(owner).setWhitelistEnabled(false);

            const mintAmount = ethers.parseUnits("10000", 6);
            await treasuryToken.connect(minter).mint(user1.address, mintAmount);
            const balance = await treasuryToken.balanceOf(user1.address);

            // Should now allow transfer to unauthorized
            await treasuryToken.connect(user1).transfer(unauthorized.address, balance / 2n);
            expect(await treasuryToken.balanceOf(unauthorized.address)).to.be.gt(0);
        });
    });

    describe("Pausability", function () {
        it("Should pause and unpause correctly", async function () {
            const { treasuryToken, owner } = await loadFixture(deployTreasuryTokenFixture);

            await treasuryToken.connect(owner).pause();
            expect(await treasuryToken.paused()).to.be.true;

            await treasuryToken.connect(owner).unpause();
            expect(await treasuryToken.paused()).to.be.false;
        });

        it("Should prevent operations when paused", async function () {
            const { treasuryToken, owner, minter, user1 } = await loadFixture(
                deployTreasuryTokenFixture
            );

            await treasuryToken.connect(owner).pause();

            const mintAmount = ethers.parseUnits("10000", 6);
            await expect(
                treasuryToken.connect(minter).mint(user1.address, mintAmount)
            ).to.be.revertedWith("Pausable: paused");
        });
    });

    describe("Upgradeability", function () {
        it("Should upgrade implementation", async function () {
            const { treasuryToken, owner } = await loadFixture(deployTreasuryTokenFixture);

            const TreasuryTokenV2 = await ethers.getContractFactory("TreasuryToken");
            const treasuryTokenV2 = await upgrades.upgradeProxy(
                await treasuryToken.getAddress(),
                TreasuryTokenV2
            );

            // Verify it's still the same proxy
            expect(await treasuryTokenV2.getAddress()).to.equal(await treasuryToken.getAddress());
        });
    });
});
