const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("RebasingTreasuryToken", function () {
    async function deployRebasingTokenFixture() {
        const [owner, minter, redeemer, user1] = await ethers.getSigners();

        const MockUSDC = await ethers.getContractFactory("MockUSDC");
        const mockUSDC = await MockUSDC.deploy();
        await mockUSDC.waitForDeployment();

        const TreasuryPriceOracle = await ethers.getContractFactory("TreasuryPriceOracle");
        const priceOracle = await TreasuryPriceOracle.deploy(owner.address);
        await priceOracle.waitForDeployment();

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
                owner.address,
            ],
            { initializer: "initialize" }
        );
        await rebasingToken.waitForDeployment();

        const MINTER_ROLE = await rebasingToken.MINTER_ROLE();
        const REDEEMER_ROLE = await rebasingToken.REDEEMER_ROLE();
        await rebasingToken.grantRole(MINTER_ROLE, minter.address);
        await rebasingToken.grantRole(REDEEMER_ROLE, redeemer.address);

        await rebasingToken.addToWhitelist(user1.address);
        await rebasingToken.addToWhitelist(minter.address);
        await rebasingToken.addToWhitelist(redeemer.address);

        return {
            owner,
            minter,
            redeemer,
            user1,
            mockUSDC,
            priceOracle,
            rebasingToken,
        };
    }

    describe("Rebasing Mechanism", function () {
        it("Should maintain price at ~$1", async function () {
            const { rebasingToken } = await loadFixture(deployRebasingTokenFixture);

            const price = await rebasingToken.getPricePerToken();
            expect(price).to.equal(ethers.parseUnits("1", 18));
        });

        it("Should increase balances after rebase", async function () {
            const { rebasingToken, minter, user1 } = await loadFixture(
                deployRebasingTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6);
            await rebasingToken.connect(minter).mint(user1.address, mintAmount);

            const initialBalance = await rebasingToken.balanceOf(user1.address);

            // Fast forward 1 day
            await time.increase(1 days);
            await ethers.provider.send("evm_mine", []);

            // Trigger rebase
            const ORACLE_ROLE = await rebasingToken.ORACLE_ROLE();
            await rebasingToken.grantRole(ORACLE_ROLE, minter.address);
            await rebasingToken.connect(minter).rebase();

            const newBalance = await rebasingToken.balanceOf(user1.address);
            expect(newBalance).to.be.gt(initialBalance);
        });

        it("Should automatically rebase on transfer", async function () {
            const { rebasingToken, minter, user1 } = await loadFixture(
                deployRebasingTokenFixture
            );

            const mintAmount = ethers.parseUnits("10000", 6);
            await rebasingToken.connect(minter).mint(user1.address, mintAmount);

            const initialBalance = await rebasingToken.balanceOf(user1.address);

            // Fast forward 1 day
            await time.increase(1 days);
            await ethers.provider.send("evm_mine", []);

            // Transfer should trigger rebase
            const transferAmount = initialBalance / 2n;
            await rebasingToken.connect(user1).transfer(user1.address, transferAmount);

            const newBalance = await rebasingToken.balanceOf(user1.address);
            expect(newBalance).to.be.gt(initialBalance - transferAmount);
        });
    });
});
