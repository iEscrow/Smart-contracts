const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("EscrowTeamTreasury", function () {
    let escrowToken;
    let treasury;
    let owner;
    let founder1;
    let founder2;
    let team1;
    let advisor1;
    
    const TOTAL_ALLOCATION = ethers.parseEther("1000000000"); // 1 billion
    const LOCK_DURATION = 1095 * 24 * 60 * 60; // 3 years in seconds
    const VESTING_INTERVAL = 180 * 24 * 60 * 60; // 6 months in seconds
    
    beforeEach(async function () {
        // Get signers
        [owner, founder1, founder2, team1, advisor1] = await ethers.getSigners();
        
        // Deploy mock ESCROW token
        const MockToken = await ethers.getContractFactory("MockEscrowToken");
        escrowToken = await MockToken.deploy();
        await escrowToken.waitForDeployment();
        
        // Deploy treasury
        const Treasury = await ethers.getContractFactory("EscrowTeamTreasury");
        treasury = await Treasury.deploy(await escrowToken.getAddress());
        await treasury.waitForDeployment();
    });
    
    describe("Deployment", function () {
        it("Should set correct token address", async function () {
            expect(await treasury.escrowToken()).to.equal(await escrowToken.getAddress());
        });
        
        it("Should set correct total allocation", async function () {
            expect(await treasury.TOTAL_ALLOCATION()).to.equal(TOTAL_ALLOCATION);
        });
        
        it("Should not be funded initially", async function () {
            expect(await treasury.treasuryFunded()).to.equal(false);
        });
        
        it("Should not have locked allocations", async function () {
            expect(await treasury.allocationsLocked()).to.equal(false);
        });
    });
    
    describe("Funding", function () {
        it("Should fund treasury successfully", async function () {
            // Approve and fund
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            
            expect(await treasury.treasuryFunded()).to.equal(true);
            expect(await escrowToken.balanceOf(await treasury.getAddress())).to.equal(TOTAL_ALLOCATION);
        });
        
        it("Should fail to fund twice", async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            
            await expect(treasury.fundTreasury()).to.be.revertedWithCustomError(
                treasury,
                "TreasuryAlreadyFunded"
            );
        });
        
        it("Should fail to fund with insufficient balance", async function () {
            // Deploy new treasury
            const Treasury = await ethers.getContractFactory("EscrowTeamTreasury");
            const newTreasury = await Treasury.deploy(await escrowToken.getAddress());
            
            // Transfer away all tokens
            const balance = await escrowToken.balanceOf(owner.address);
            await escrowToken.transfer(founder1.address, balance);
            
            await expect(newTreasury.fundTreasury()).to.be.revertedWithCustomError(
                newTreasury,
                "InsufficientBalance"
            );
        });
    });
    
    describe("Adding Beneficiaries", function () {
        beforeEach(async function () {
            // Fund treasury
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
        });
        
        it("Should add beneficiary successfully", async function () {
            const allocation = ethers.parseEther("400000000"); // 400M
            
            await treasury.addBeneficiary(founder1.address, allocation);
            
            const info = await treasury.getBeneficiaryInfo(founder1.address);
            expect(info.totalAllocation).to.equal(allocation);
            expect(info.isActive).to.equal(true);
        });
        
        it("Should add multiple beneficiaries", async function () {
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
            await treasury.addBeneficiary(team1.address, ethers.parseEther("500000000"));
            await treasury.addBeneficiary(advisor1.address, ethers.parseEther("100000000"));
            
            const stats = await treasury.getTreasuryStats();
            expect(stats.totalAlloc).to.equal(TOTAL_ALLOCATION);
            expect(stats.beneficiaryCount).to.equal(3);
        });
        
        it("Should fail to exceed total allocation", async function () {
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("600000000"));
            
            await expect(
                treasury.addBeneficiary(team1.address, ethers.parseEther("500000000"))
            ).to.be.revertedWithCustomError(treasury, "ExceedsTotalAllocation");
        });
        
        it("Should fail to add same beneficiary twice", async function () {
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
            
            await expect(
                treasury.addBeneficiary(founder1.address, ethers.parseEther("100000000"))
            ).to.be.revertedWithCustomError(treasury, "AlreadyAllocated");
        });
        
        it("Should fail to add beneficiary with zero allocation", async function () {
            await expect(
                treasury.addBeneficiary(founder1.address, 0)
            ).to.be.revertedWithCustomError(treasury, "InvalidAmount");
        });
        
        it("Should fail to add beneficiary after locking", async function () {
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
            await treasury.lockAllocations();
            
            await expect(
                treasury.addBeneficiary(team1.address, ethers.parseEther("500000000"))
            ).to.be.revertedWithCustomError(treasury, "AllocationsAlreadyLocked");
        });
    });
    
    describe("Updating Beneficiaries", function () {
        beforeEach(async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
        });
        
        it("Should update beneficiary allocation", async function () {
            const newAllocation = ethers.parseEther("500000000");
            await treasury.updateBeneficiary(founder1.address, newAllocation);
            
            const info = await treasury.getBeneficiaryInfo(founder1.address);
            expect(info.totalAllocation).to.equal(newAllocation);
        });
        
        it("Should fail to update after locking", async function () {
            await treasury.lockAllocations();
            
            await expect(
                treasury.updateBeneficiary(founder1.address, ethers.parseEther("500000000"))
            ).to.be.revertedWithCustomError(treasury, "AllocationsAlreadyLocked");
        });
    });
    
    describe("Removing Beneficiaries", function () {
        beforeEach(async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
        });
        
        it("Should remove beneficiary successfully", async function () {
            await treasury.removeBeneficiary(founder1.address);
            
            const info = await treasury.getBeneficiaryInfo(founder1.address);
            expect(info.isActive).to.equal(false);
            
            const stats = await treasury.getTreasuryStats();
            expect(stats.beneficiaryCount).to.equal(0);
        });
    });
    
    describe("Locking Allocations", function () {
        beforeEach(async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
        });
        
        it("Should lock allocations successfully", async function () {
            await treasury.lockAllocations();
            expect(await treasury.allocationsLocked()).to.equal(true);
        });
        
        it("Should fail to lock twice", async function () {
            await treasury.lockAllocations();
            
            await expect(treasury.lockAllocations()).to.be.revertedWithCustomError(
                treasury,
                "AllocationsAlreadyLocked"
            );
        });
    });
    
    describe("Vesting and Claims", function () {
        beforeEach(async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
            await treasury.addBeneficiary(team1.address, ethers.parseEther("500000000"));
            await treasury.lockAllocations();
        });
        
        it("Should fail to claim before lock period", async function () {
            await expect(
                treasury.connect(founder1).claimTokens()
            ).to.be.revertedWithCustomError(treasury, "NoTokensAvailable");
        });
        
        it("Should claim first milestone (20%) after 3 years", async function () {
            // Fast forward 3 years
            await time.increase(LOCK_DURATION);
            
            const allocation = ethers.parseEther("400000000");
            const expectedClaim = allocation * 20n / 100n; // 20%
            
            const claimable = await treasury.getClaimableAmount(founder1.address);
            expect(claimable).to.equal(expectedClaim);
            
            await treasury.connect(founder1).claimTokens();
            
            const balance = await escrowToken.balanceOf(founder1.address);
            expect(balance).to.equal(expectedClaim);
        });
        
        it("Should claim all milestones progressively", async function () {
            const allocation = ethers.parseEther("400000000");
            
            // Claim at each milestone
            for (let i = 1; i <= 5; i++) {
                // Move to milestone
                await time.increase(LOCK_DURATION + (VESTING_INTERVAL * i) - await time.latest());
                
                const expectedTotal = allocation * BigInt(i * 20) / 100n;
                const claimable = await treasury.getClaimableAmount(founder1.address);
                
                if (claimable > 0) {
                    await treasury.connect(founder1).claimTokens();
                }
                
                const info = await treasury.getBeneficiaryInfo(founder1.address);
                expect(info.claimedAmount).to.equal(expectedTotal);
            }
            
            // Final balance should be full allocation
            const finalBalance = await escrowToken.balanceOf(founder1.address);
            expect(finalBalance).to.equal(allocation);
        });
        
        it("Should allow claiming for beneficiary by anyone", async function () {
            await time.increase(LOCK_DURATION);
            
            // Owner claims for founder1
            await treasury.claimFor(founder1.address);
            
            const allocation = ethers.parseEther("400000000");
            const expectedClaim = allocation * 20n / 100n;
            const balance = await escrowToken.balanceOf(founder1.address);
            expect(balance).to.equal(expectedClaim);
        });
    });
    
    describe("View Functions", function () {
        beforeEach(async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
            await treasury.addBeneficiary(team1.address, ethers.parseEther("500000000"));
            await treasury.lockAllocations();
        });
        
        it("Should return correct vesting schedule", async function () {
            const schedule = await treasury.getVestingSchedule();
            
            expect(schedule.totalMilestones).to.equal(5);
            expect(schedule.intervalDays).to.equal(180);
            expect(schedule.unlockTimes.length).to.equal(5);
        });
        
        it("Should return all beneficiaries", async function () {
            const beneficiaries = await treasury.getAllBeneficiaries();
            
            expect(beneficiaries.addresses.length).to.equal(2);
            expect(beneficiaries.addresses).to.include(founder1.address);
            expect(beneficiaries.addresses).to.include(team1.address);
        });
        
        it("Should return correct treasury stats", async function () {
            const stats = await treasury.getTreasuryStats();
            
            expect(stats.totalAlloc).to.equal(ethers.parseEther("900000000"));
            expect(stats.beneficiaryCount).to.equal(2);
            expect(stats.locked).to.equal(true);
            expect(stats.funded).to.equal(true);
        });
    });
    
    describe("Emergency Functions", function () {
        beforeEach(async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            await treasury.addBeneficiary(founder1.address, ethers.parseEther("400000000"));
            await treasury.lockAllocations();
        });
        
        it("Should pause contract", async function () {
            await treasury.pause();
            
            await time.increase(LOCK_DURATION);
            
            await expect(
                treasury.connect(founder1).claimTokens()
            ).to.be.revertedWithCustomError(treasury, "EnforcedPause");
        });
        
        it("Should unpause contract", async function () {
            await treasury.pause();
            await treasury.unpause();
            
            await time.increase(LOCK_DURATION);
            await treasury.connect(founder1).claimTokens(); // Should work
        });
        
        it("Should revoke allocation", async function () {
            await treasury.revokeAllocation(founder1.address);
            
            const info = await treasury.getBeneficiaryInfo(founder1.address);
            expect(info.revoked).to.equal(true);
        });
        
        it("Should withdraw unallocated tokens", async function () {
            // Only 400M allocated, 600M unallocated
            const unallocated = ethers.parseEther("600000000");
            
            await treasury.emergencyWithdraw();
            
            const ownerBalance = await escrowToken.balanceOf(owner.address);
            expect(ownerBalance).to.be.gte(unallocated);
        });
    });
    
    describe("Access Control", function () {
        it("Should only allow owner to add beneficiaries", async function () {
            await escrowToken.approve(await treasury.getAddress(), TOTAL_ALLOCATION);
            await treasury.fundTreasury();
            
            await expect(
                treasury.connect(founder1).addBeneficiary(team1.address, ethers.parseEther("100000000"))
            ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
        });
        
        it("Should only allow owner to lock allocations", async function () {
            await expect(
                treasury.connect(founder1).lockAllocations()
            ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
        });
    });
});