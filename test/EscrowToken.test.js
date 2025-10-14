const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("EscrowToken", function () {
  // Fixture for deploying the contract
  async function deployTokenFixture() {
    const [owner, user1, user2, minter, pauser, burner, treasury] = await ethers.getSigners();

    const EscrowToken = await ethers.getContractFactory("EscrowToken");
    const token = await EscrowToken.deploy(owner.address);

    return { token, owner, user1, user2, minter, pauser, burner, treasury };
  }

  describe("Deployment", function () {
    it("Should deploy with correct name and symbol", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      expect(await token.name()).to.equal("ESCROW");
      expect(await token.symbol()).to.equal("ESCROW");
    });

    it("Should set correct max supply", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      const maxSupply = ethers.parseEther("100000000000"); // 100 billion
      expect(await token.MAX_SUPPLY()).to.equal(maxSupply);
    });

    it("Should grant admin role to deployer", async function () {
      const { token, owner } = await loadFixture(deployTokenFixture);
      const adminRole = await token.DEFAULT_ADMIN_ROLE();
      expect(await token.hasRole(adminRole, owner.address)).to.be.true;
    });

    it("Should start with trading disabled", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      expect(await token.tradingEnabled()).to.be.false;
    });
  });

  describe("Minting", function () {
    it("Should mint tokens successfully", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000000");
      
      await token.mint(user1.address, amount);
      expect(await token.balanceOf(user1.address)).to.equal(amount);
      expect(await token.totalMinted()).to.equal(amount);
    });

    it("Should not exceed max supply", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      const maxSupply = await token.MAX_SUPPLY();
      
      await expect(
        token.mint(user1.address, maxSupply + 1n)
      ).to.be.revertedWithCustomError(token, "MaxSupplyExceeded");
    });

    it("Should only allow minter role to mint", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await expect(
        token.connect(user1).mint(user2.address, amount)
      ).to.be.reverted;
    });

    it("Should batch mint correctly", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount1 = ethers.parseEther("1000");
      const amount2 = ethers.parseEther("2000");
      
      await token.batchMint([user1.address, user2.address], [amount1, amount2]);
      
      expect(await token.balanceOf(user1.address)).to.equal(amount1);
      expect(await token.balanceOf(user2.address)).to.equal(amount2);
      expect(await token.totalMinted()).to.equal(amount1 + amount2);
    });
  });

  describe("Trading Controls", function () {
    it("Should not allow transfers when trading is disabled", async function () {
      const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      
      await expect(
        token.connect(user1).transfer(user2.address, amount)
      ).to.be.revertedWithCustomError(token, "TradingNotEnabled");
    });

    it("Should allow admin to transfer when trading is disabled", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(owner.address, amount);
      await token.transfer(user1.address, amount);
      
      expect(await token.balanceOf(user1.address)).to.equal(amount);
    });

    it("Should enable trading successfully", async function () {
      const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      await token.enableTrading();
      
      expect(await token.tradingEnabled()).to.be.true;
      
      await token.connect(user1).transfer(user2.address, amount);
      expect(await token.balanceOf(user2.address)).to.equal(amount);
    });

    it("Should only enable trading once", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      
      await token.enableTrading();
      await expect(token.enableTrading()).to.be.reverted;
    });
  });

  describe("Blacklist", function () {
    it("Should blacklist addresses", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      
      await token.updateBlacklist(user1.address, true);
      expect(await token.blacklist(user1.address)).to.be.true;
    });

    it("Should prevent blacklisted addresses from transferring", async function () {
      const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      await token.enableTrading();
      await token.updateBlacklist(user1.address, true);
      
      await expect(
        token.connect(user1).transfer(user2.address, amount)
      ).to.be.revertedWithCustomError(token, "AccountBlacklisted");
    });

    it("Should prevent transfers to blacklisted addresses", async function () {
      const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      await token.enableTrading();
      await token.updateBlacklist(user2.address, true);
      
      await expect(
        token.connect(user1).transfer(user2.address, amount)
      ).to.be.revertedWithCustomError(token, "AccountBlacklisted");
    });

    it("Should batch update blacklist", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);
      
      await token.batchUpdateBlacklist([user1.address, user2.address], true);
      
      expect(await token.blacklist(user1.address)).to.be.true;
      expect(await token.blacklist(user2.address)).to.be.true;
    });
  });

  describe("Pausable", function () {
    it("Should pause and unpause", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      
      await token.pause();
      expect(await token.paused()).to.be.true;
      
      await token.unpause();
      expect(await token.paused()).to.be.false;
    });

    it("Should prevent transfers when paused", async function () {
      const { token, owner, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      await token.enableTrading();
      await token.pause();
      
      await expect(
        token.connect(user1).transfer(user2.address, amount)
      ).to.be.reverted;
    });
  });

  describe("Burning", function () {
    it("Should burn tokens", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      await token.connect(user1).burn(amount);
      
      expect(await token.balanceOf(user1.address)).to.equal(0);
    });

    it("Should allow burner role to burn from addresses", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      await token.burnFrom(user1.address, amount);
      
      expect(await token.balanceOf(user1.address)).to.equal(0);
    });

    it("Should require allowance for non-burner role burnFrom", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      
      await token.mint(user1.address, amount);
      
      // user2 doesn't have BURNER_ROLE and no allowance
      await expect(
        token.connect(user2).burnFrom(user1.address, amount)
      ).to.be.reverted;
      
      // Give allowance
      await token.connect(user1).approve(user2.address, amount);
      
      // Now should work
      await token.connect(user2).burnFrom(user1.address, amount);
      expect(await token.balanceOf(user1.address)).to.equal(0);
    });
  });

  describe("Fee System", function () {
    it("Should configure fees", async function () {
      const { token, treasury } = await loadFixture(deployTokenFixture);
      
      await token.configureFees(true, 100, treasury.address); // 1% fee
      
      const feeInfo = await token.getFeeInfo();
      expect(feeInfo.enabled).to.be.true;
      expect(feeInfo.rate).to.equal(100);
      expect(feeInfo.collector).to.equal(treasury.address);
    });

    it("Should collect fees on transfers", async function () {
      const { token, owner, user1, user2, treasury } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      const feeRate = 100; // 1%
      
      await token.mint(user1.address, amount);
      await token.enableTrading();
      await token.configureFees(true, feeRate, treasury.address);
      
      await token.connect(user1).transfer(user2.address, amount);
      
      const expectedFee = (amount * BigInt(feeRate)) / 10000n;
      const expectedAmount = amount - expectedFee;
      
      expect(await token.balanceOf(user2.address)).to.equal(expectedAmount);
      expect(await token.balanceOf(treasury.address)).to.be.gt(0);
    });

    it("Should collect fees on transferFrom", async function () {
      const { token, owner, user1, user2, treasury } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000");
      const feeRate = 100; // 1%
      
      await token.mint(user1.address, amount);
      await token.enableTrading();
      await token.configureFees(true, feeRate, treasury.address);
      
      // user1 approves user2 to transfer
      await token.connect(user1).approve(user2.address, amount);
      
      // user2 transfers from user1 (should apply fees)
      await token.connect(user2).transferFrom(user1.address, treasury.address, ethers.parseEther("100"));
      
      // Check fee was collected
      const treasuryBalance = await token.balanceOf(treasury.address);
      expect(treasuryBalance).to.be.gt(ethers.parseEther("99")); // 100 - 1% fee
    });

    it("Should not exceed max fee rate", async function () {
      const { token, treasury } = await loadFixture(deployTokenFixture);
      
      await expect(
        token.configureFees(true, 501, treasury.address) // >5%
      ).to.be.revertedWithCustomError(token, "InvalidFeeRate");
    });
  });

  describe("View Functions", function () {
    it("Should return remaining supply", async function () {
      const { token, user1 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000000");
      
      await token.mint(user1.address, amount);
      
      const maxSupply = await token.MAX_SUPPLY();
      const remaining = await token.remainingSupply();
      
      expect(remaining).to.equal(maxSupply - amount);
    });

    it("Should return token info", async function () {
      const { token, user1 } = await loadFixture(deployTokenFixture);
      const amount = ethers.parseEther("1000000");
      
      await token.mint(user1.address, amount);
      
      const info = await token.getTokenInfo();
      
      expect(info.maxSupply).to.equal(await token.MAX_SUPPLY());
      expect(info.currentSupply).to.equal(amount);
      expect(info.minted).to.equal(amount);
      expect(info.trading).to.be.false;
    });

    it("Should check if account can transfer", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      
      expect(await token.canTransfer(owner.address)).to.be.true;
      expect(await token.canTransfer(user1.address)).to.be.false;
      
      await token.enableTrading();
      expect(await token.canTransfer(user1.address)).to.be.true;
    });
  });

  describe("Role Management", function () {
    it("Should grant and revoke roles", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);
      const minterRole = await token.MINTER_ROLE();
      
      await token.grantRole(minterRole, user1.address);
      expect(await token.hasRole(minterRole, user1.address)).to.be.true;
      
      await token.revokeRole(minterRole, user1.address);
      expect(await token.hasRole(minterRole, user1.address)).to.be.false;
    });
  });

  describe("EIP-2612 Permit", function () {
    it("Should have correct domain separator", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      expect(domainSeparator).to.not.equal(ethers.ZeroHash);
    });
  });
});
