const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("EscrowTeamTreasury", function () {
  let EscrowTeamTreasury, MockEscrowToken;
  let treasury, escrowToken;
  let owner, addr1, addr2;

  // constants
  const TOKEN_DECIMALS = 18;
  const LOCK_DURATION = 3 * 365 * 24 * 60 * 60; // 3 years in seconds
  const VESTING_INTERVAL = 180 * 24 * 60 * 60;   // 6 months in seconds
  const TOTAL_ALLOCATION = ethers.parseUnits("1000000", TOKEN_DECIMALS);

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy mock token (no constructor parameters needed as per MockEscrowToken.sol)
    MockEscrowToken = await ethers.getContractFactory("MockEscrowToken");
    escrowToken = await MockEscrowToken.deploy();
    await escrowToken.waitForDeployment();

    // Deploy treasury with token address
    EscrowTeamTreasury = await ethers.getContractFactory("EscrowTeamTreasury");
    treasury = await EscrowTeamTreasury.deploy(await escrowToken.getAddress());
    await treasury.waitForDeployment();
  });

  // ---------------- DEPLOYMENT ---------------- //
  describe("Deployment", function () {
    it("Should set correct token address", async function () {
      expect(await treasury.escrowToken()).to.equal(await escrowToken.getAddress());
    });

    it("Should set correct total allocation", async function () {
      const expectedAllocation = ethers.parseUnits("1000000000", TOKEN_DECIMALS); // 1B tokens
      expect(await treasury.TOTAL_ALLOCATION()).to.equal(expectedAllocation);
    });

    it("Should not be funded initially", async function () {
      expect(await treasury.treasuryFunded()).to.be.false;
    });

    it("Should not have locked allocations initially", async function () {
      expect(await treasury.allocationsLocked()).to.be.false;
    });
  });

  // ---------------- FUNDING ---------------- //
  describe("Funding Treasury", function () {
    it("Should fund treasury successfully", async function () {
      // Mint more tokens to owner if needed
      const amount = await treasury.TOTAL_ALLOCATION();
      await (await escrowToken.mint(owner.address, amount)).wait();
      
      // Approve treasury to spend tokens
      await (await escrowToken.approve(treasury.getAddress(), amount)).wait();
      
      await expect(treasury.fundTreasury())
        .to.emit(treasury, "TreasuryFunded")
        .withArgs(amount, await time.latest());
    });

    it("Should revert if funding twice", async function () {
      const amount = await treasury.TOTAL_ALLOCATION();
      await (await escrowToken.mint(owner.address, amount)).wait();
      await (await escrowToken.approve(treasury.getAddress(), amount)).wait();
      await (await treasury.fundTreasury()).wait();
      
      await expect(treasury.fundTreasury())
        .to.be.revertedWithCustomError(treasury, "TreasuryAlreadyFunded");
    });

    it("Should revert if insufficient balance", async function () {
      // Deploy a modified version of the token that doesn't mint in the constructor
      const MockTokenNoMint = await ethers.getContractFactory("MockEscrowTokenNoMint");
      const newToken = await MockTokenNoMint.deploy();
      await newToken.waitForDeployment();
      
      // Deploy a new treasury with the new token
      const newTreasury = await EscrowTeamTreasury.deploy(await newToken.getAddress());
      await newTreasury.waitForDeployment();
      
      // Get the owner's address and signer
      const owner = await newTreasury.owner();
      const ownerSigner = await ethers.getSigner(owner);
      
      // Get the required amount
      const amount = await newTreasury.TOTAL_ALLOCATION();
      
      // Mint just 1 wei less than required to the owner
      await (await newToken.connect(ownerSigner).mint(owner, amount - 1n)).wait();
      
      // Approve the treasury to spend the tokens
      await (await newToken.connect(ownerSigner).approve(await newTreasury.getAddress(), amount)).wait();
      
      // Should revert with InsufficientBalance since owner has 1 wei less than required
      await expect(newTreasury.fundTreasury())
        .to.be.revertedWithCustomError(newTreasury, "InsufficientBalance");
    });
  });

  // ---------------- BENEFICIARY MGMT ---------------- //
  describe("Beneficiary Management", function () {
    const beneficiaryAmount = ethers.parseUnits("100000", TOKEN_DECIMALS);
    
    beforeEach(async function () {
      // Fund the treasury first
      const amount = await treasury.TOTAL_ALLOCATION();
      await (await escrowToken.mint(owner.address, amount)).wait();
      await (await escrowToken.approve(treasury.getAddress(), amount)).wait();
      await (await treasury.fundTreasury()).wait();
    });

    it("Should add beneficiary successfully", async function () {
      await expect(treasury.addBeneficiary(addr1.address, beneficiaryAmount))
        .to.emit(treasury, "BeneficiaryAdded")
        .withArgs(addr1.address, beneficiaryAmount);
    });

    it("Should revert if adding same beneficiary twice", async function () {
      await treasury.addBeneficiary(addr1.address, beneficiaryAmount);
      await expect(treasury.addBeneficiary(addr1.address, beneficiaryAmount))
        .to.be.revertedWithCustomError(treasury, "AlreadyAllocated");
    });

    it("Should revert if allocation exceeds total", async function () {
      const hugeAmount = ethers.parseUnits("2000000000", TOKEN_DECIMALS); // 2B > 1B total
      await expect(treasury.addBeneficiary(addr1.address, hugeAmount))
        .to.be.revertedWithCustomError(treasury, "ExceedsTotalAllocation");
    });

    it("Should update beneficiary allocation before locking", async function () {
      await treasury.addBeneficiary(addr1.address, beneficiaryAmount);
      const newAmount = ethers.parseUnits("200000", TOKEN_DECIMALS);
      await expect(treasury.updateBeneficiary(addr1.address, newAmount))
        .to.emit(treasury, "BeneficiaryUpdated")
        .withArgs(addr1.address, newAmount);
    });

    it("Should revert updating after locking", async function () {
      await treasury.addBeneficiary(addr1.address, beneficiaryAmount);
      await treasury.lockAllocations();
      const newAmount = ethers.parseUnits("200000", TOKEN_DECIMALS);
      await expect(treasury.updateBeneficiary(addr1.address, newAmount))
        .to.be.revertedWithCustomError(treasury, "AllocationsAlreadyLocked");
    });

    it("Should remove beneficiary before locking", async function () {
      await treasury.addBeneficiary(addr1.address, beneficiaryAmount);
      await expect(treasury.removeBeneficiary(addr1.address))
        .to.emit(treasury, "BeneficiaryRemoved")
        .withArgs(addr1.address, beneficiaryAmount);
    });
  });

  // ---------------- LOCKING ---------------- //
  describe("Locking Allocations", function () {
    const beneficiaryAmount = ethers.parseUnits("100000", TOKEN_DECIMALS);
    
    beforeEach(async function () {
      // Setup treasury with one beneficiary
      const amount = await treasury.TOTAL_ALLOCATION();
      await (await escrowToken.mint(owner.address, amount)).wait();
      await (await escrowToken.approve(treasury.getAddress(), amount)).wait();
      await (await treasury.fundTreasury()).wait();
      await (await treasury.addBeneficiary(addr1.address, beneficiaryAmount)).wait();
    });

    it("Should lock allocations successfully", async function () {
      await expect(treasury.lockAllocations())
        .to.emit(treasury, "AllocationsLocked");
      
      expect(await treasury.allocationsLocked()).to.be.true;
    });

    it("Should revert locking twice", async function () {
      await treasury.lockAllocations();
      await expect(treasury.lockAllocations())
        .to.be.revertedWithCustomError(treasury, "AllocationsAlreadyLocked");
    });
  });

  // ---------------- CLAIMS ---------------- //
  describe("Vesting & Claims", function () {
    const beneficiaryAmount = ethers.parseUnits("100000", TOKEN_DECIMALS);
    const milestoneAmount = beneficiaryAmount / 5n; // 20% per milestone
    
    beforeEach(async function () {
      // Setup treasury with one beneficiary and locked allocations
      const amount = await treasury.TOTAL_ALLOCATION();
      await (await escrowToken.mint(owner.address, amount)).wait();
      await (await escrowToken.approve(treasury.getAddress(), amount)).wait();
      await (await treasury.fundTreasury()).wait();
      await (await treasury.addBeneficiary(addr1.address, beneficiaryAmount)).wait();
      await (await treasury.lockAllocations()).wait();
    });

    it("Should not claim before 3-year lock", async function () {
      await expect(treasury.connect(addr1).claimTokens())
        .to.be.revertedWithCustomError(treasury, "NoTokensAvailable");
    });

    it("Should claim 20% after 3 years", async function () {
      await time.increase(LOCK_DURATION);
      
      await expect(treasury.connect(addr1).claimTokens())
        .to.emit(treasury, "TokensClaimed")
        .withArgs(addr1.address, milestoneAmount, 1);
      
      const info = await treasury.beneficiaries(addr1.address);
      expect(info.claimedAmount).to.equal(milestoneAmount);
    });

    it("Should claim all milestones correctly", async function () {
      // 5 milestones (0-4) after initial 3-year lock
      for (let i = 1; i <= 5; i++) {
        // Move to next milestone (3y + 6m * (i-1))
        await time.increase(i === 1 ? LOCK_DURATION : VESTING_INTERVAL);
        
        // Claim for this milestone
        await (await treasury.connect(addr1).claimTokens()).wait();
        
        // Verify claimed amount
        const info = await treasury.beneficiaries(addr1.address);
        const expectedAmount = (beneficiaryAmount * BigInt(i)) / 5n;
        expect(info.claimedAmount).to.equal(expectedAmount);
      }
    });

    it("Should allow claimFor by anyone", async function () {
      await time.increase(LOCK_DURATION);
      
      await expect(treasury.connect(addr2).claimFor(addr1.address))
        .to.emit(treasury, "TokensClaimed")
        .withArgs(addr1.address, milestoneAmount, 1);
    });
  });

  // ---------------- ADMIN ---------------- //
  describe("Emergency & Admin", function () {
    const beneficiaryAmount = ethers.parseUnits("100000", TOKEN_DECIMALS);
    
    beforeEach(async function () {
      // Setup treasury with one beneficiary and locked allocations
      const amount = await treasury.TOTAL_ALLOCATION();
      await (await escrowToken.mint(owner.address, amount)).wait();
      await (await escrowToken.approve(treasury.getAddress(), amount)).wait();
      await (await treasury.fundTreasury()).wait();
      await (await treasury.addBeneficiary(addr1.address, beneficiaryAmount)).wait();
      await (await treasury.lockAllocations()).wait();
      await time.increase(LOCK_DURATION); // Pass initial lock period
    });

    it("Should pause and revert claims", async function () {
      await treasury.pause();
      await expect(treasury.connect(addr1).claimTokens())
        .to.be.revertedWithCustomError(treasury, "EnforcedPause");
    });

    it("Should unpause and allow claims", async function () {
      await treasury.pause();
      await treasury.unpause();
      
      await expect(treasury.connect(addr1).claimTokens())
        .to.emit(treasury, "TokensClaimed");
    });

    it("Should revoke allocation", async function () {
      const vestedBefore = await treasury.getClaimableAmount(addr1.address);
      
      await expect(treasury.revokeAllocation(addr1.address))
        .to.emit(treasury, "AllocationRevoked")
        .withArgs(addr1.address, beneficiaryAmount - vestedBefore);
      
      // Should mark as revoked
      const info = await treasury.beneficiaries(addr1.address);
      expect(info.revoked).to.be.true;
    });

    it("Should withdraw unallocated tokens", async function () {
      // Get the current treasury balance
      const initialTreasuryBalance = await escrowToken.balanceOf(await treasury.getAddress());
      
      // Add some extra unallocated tokens (beyond what was funded in beforeEach)
      const extraTokens = ethers.parseUnits("1000", TOKEN_DECIMALS);
      await (await escrowToken.mint(await treasury.getAddress(), extraTokens)).wait();
      
      // Calculate the expected unallocated amount
      const totalAllocated = beneficiaryAmount; // From beforeEach
      const expectedUnallocated = (await escrowToken.balanceOf(await treasury.getAddress())) - totalAllocated;
      
      const balanceBefore = await escrowToken.balanceOf(owner.address);
      
      await expect(treasury.emergencyWithdraw())
        .to.emit(treasury, "EmergencyWithdraw");
      
      const balanceAfter = await escrowToken.balanceOf(owner.address);
      expect(balanceAfter - balanceBefore).to.equal(expectedUnallocated);
    });
  });

  // ---------------- ACCESS CONTROL ---------------- //
  describe("Access Control", function () {
    it("Only owner can add beneficiaries", async function () {
      const amount = ethers.parseUnits("10000", TOKEN_DECIMALS);
      await expect(
        treasury.connect(addr1).addBeneficiary(addr2.address, amount)
      ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
    });

    it("Only owner can lock allocations", async function () {
      await expect(treasury.connect(addr1).lockAllocations())
        .to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
    });
  });
});
