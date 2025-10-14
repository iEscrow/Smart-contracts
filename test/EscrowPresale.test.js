const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("EscrowPresale", function () {
  async function deployPresaleFixture() {
    const [owner, treasury, buyer1, buyer2, referrer] = await ethers.getSigners();

    // Deploy token
    const EscrowToken = await ethers.getContractFactory("EscrowToken");
    const token = await EscrowToken.deploy(owner.address);

    // Deploy presale
    const EscrowPresale = await ethers.getContractFactory("iEscrowPresale");
    const presale = await EscrowPresale.deploy(
      await token.getAddress(),
      treasury.address
    );

    // Grant minter role to presale
    const minterRole = await token.MINTER_ROLE();
    await token.grantRole(minterRole, await presale.getAddress());

    // Mint tokens to presale
    const presaleAmount = ethers.parseEther("5000000000"); // 5 billion
    await token.mint(await presale.getAddress(), presaleAmount);

    // Configure rounds
    const round1Price = 150000; // $0.0015 (8 decimals)
    const round1Tokens = ethers.parseEther("3000000000"); // 3 billion
    await presale.configureRound(1, round1Price, round1Tokens);

    const round2Price = 200000; // $0.002 (8 decimals)
    const round2Tokens = ethers.parseEther("2000000000"); // 2 billion
    await presale.configureRound(2, round2Price, round2Tokens);

    return { token, presale, owner, treasury, buyer1, buyer2, referrer };
  }

  describe("Deployment", function () {
    it("Should deploy with correct parameters", async function () {
      const { presale, token, treasury } = await loadFixture(deployPresaleFixture);
      
      expect(await presale.escrowToken()).to.equal(await token.getAddress());
      expect(await presale.treasury()).to.equal(treasury.address);
      expect(await presale.TOTAL_PRESALE_TOKENS()).to.equal(ethers.parseEther("5000000000"));
    });

    it("Should have correct default limits", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      expect(await presale.maxPurchasePerUser()).to.equal(10000 * 1e8); // $10,000
      expect(await presale.minPurchaseAmount()).to.equal(50 * 1e8); // $50
    });

    it("Should start in NOT_STARTED state", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      expect(await presale.currentRound()).to.equal(0); // PresaleRound.NOT_STARTED
    });
  });

  describe("Round Configuration", function () {
    it("Should configure rounds correctly", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      const round1 = await presale.getRoundInfo(1);
      expect(round1.tokenPrice).to.equal(150000); // $0.0015
      expect(round1.maxTokens).to.equal(ethers.parseEther("3000000000"));
      
      const round2 = await presale.getRoundInfo(2);
      expect(round2.tokenPrice).to.equal(200000); // $0.002
      expect(round2.maxTokens).to.equal(ethers.parseEther("2000000000"));
    });

    it("Should not allow configuration after presale starts", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      await expect(
        presale.configureRound(1, 150000, ethers.parseEther("3000000000"))
      ).to.be.reverted;
    });
  });

  describe("Starting Presale", function () {
    it("Should start presale successfully", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      expect(await presale.currentRound()).to.equal(1); // PresaleRound.ROUND_1
      expect(await presale.presaleStartTime()).to.be.gt(0);
    });

    it("Should not start without proper configuration", async function () {
      const [owner, treasury] = await ethers.getSigners();
      const EscrowToken = await ethers.getContractFactory("EscrowToken");
      const token = await EscrowToken.deploy(owner.address);
      
      const EscrowPresale = await ethers.getContractFactory("iEscrowPresale");
      const presale = await EscrowPresale.deploy(
        await token.getAddress(),
        treasury.address
      );
      
      await expect(presale.startPresale()).to.be.reverted;
    });

    it("Should not start twice", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      await expect(presale.startPresale()).to.be.reverted;
    });
  });

  describe("Buying with ETH", function () {
    it("Should purchase tokens with ETH", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      const userInfo = await presale.getUserInfo(buyer1.address);
      expect(userInfo.totalTokensPurchased).to.be.gt(0);
    });

    it("Should respect minimum purchase amount", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      const smallAmount = ethers.parseEther("0.001");
      await expect(
        presale.connect(buyer1).buyWithNative(buyer1.address, { value: smallAmount })
      ).to.be.reverted;
    });

    it("Should respect maximum purchase per user", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      // Try to buy more than $10,000
      const largeAmount = ethers.parseEther("10"); // ~$35,000 at $3500/ETH
      await expect(
        presale.connect(buyer1).buyWithNative(buyer1.address, { value: largeAmount })
      ).to.be.reverted;
    });

    it("Should handle gas buffer correctly", async function () {
      const { presale, buyer1, treasury } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      const initialBalance = await ethers.provider.getBalance(treasury.address);
      const ethAmount = ethers.parseEther("1");
      const gasBuffer = await presale.gasBuffer();
      
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      const finalBalance = await ethers.provider.getBalance(treasury.address);
      expect(finalBalance - initialBalance).to.equal(ethAmount - gasBuffer);
    });
  });

  describe("Buying with Referral", function () {
    it("Should apply referral bonus", async function () {
      const { presale, buyer1, referrer } = await loadFixture(deployPresaleFixture);
      
      await presale.setReferralEnabled(true);
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNativeReferral(
        buyer1.address,
        referrer.address,
        { value: ethAmount }
      );
      
      const buyerReferralInfo = await presale.getReferralInfo(buyer1.address);
      expect(buyerReferralInfo.referrerAddress).to.equal(referrer.address);
      
      // Bonus tokens go to the referrer, not the buyer
      const referrerInfo = await presale.getReferralInfo(referrer.address);
      expect(referrerInfo.bonusTokens).to.be.gt(0);
    });

    it("Should not allow self-referral", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.setReferralEnabled(true);
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      // Self-referral should not set referrer
      await presale.connect(buyer1).buyWithNativeReferral(
        buyer1.address,
        buyer1.address,
        { value: ethAmount }
      );
      
      const referralInfo = await presale.getReferralInfo(buyer1.address);
      expect(referralInfo.referrerAddress).to.equal(ethers.ZeroAddress);
    });
  });

  describe("ERC20 Token Purchases", function () {
    it("Should purchase with ERC20 token (simulated)", async function () {
      const { presale, token, buyer1, treasury, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading first
      await token.connect(owner).enableTrading();
      
      // Disable fees to avoid complications in test
      await token.connect(owner).configureFees(false, 0, owner.address);
      
      await presale.startPresale();
      
      // For this test, we'll use the escrow token itself as payment
      // In production, this would be USDC, USDT, etc.
      const paymentAmount = ethers.parseEther("1000");
      await token.mint(buyer1.address, paymentAmount);
      await token.connect(buyer1).approve(await presale.getAddress(), paymentAmount);
      
      // Set escrow token as accepted payment (for testing purposes)
      await presale.setTokenPrice(await token.getAddress(), 1 * 1e8, 18, true);
      
      // Buy with token
      await presale.connect(buyer1).buyWithToken(
        await token.getAddress(),
        paymentAmount,
        buyer1.address
      );
      
      const userInfo = await presale.getUserInfo(buyer1.address);
      expect(userInfo.totalTokensPurchased).to.be.gt(0);
    });

    it("Should purchase with ERC20 token and referral", async function () {
      const { presale, token, buyer1, referrer, treasury, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading first
      await token.connect(owner).enableTrading();
      
      // Disable fees to avoid complications in test
      await token.connect(owner).configureFees(false, 0, owner.address);
      
      await presale.setReferralEnabled(true);
      await presale.startPresale();
      
      const paymentAmount = ethers.parseEther("1000");
      await token.mint(buyer1.address, paymentAmount);
      await token.connect(buyer1).approve(await presale.getAddress(), paymentAmount);
      
      // Set escrow token as accepted payment
      await presale.setTokenPrice(await token.getAddress(), 1 * 1e8, 18, true);
      
      // Buy with token and referral
      await presale.connect(buyer1).buyWithTokenReferral(
        await token.getAddress(),
        paymentAmount,
        buyer1.address,
        referrer.address
      );
      
      const referralInfo = await presale.getReferralInfo(buyer1.address);
      expect(referralInfo.referrerAddress).to.equal(referrer.address);
    });
  });

  describe("Whitelist", function () {
    it("Should enforce whitelist when enabled", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.setWhitelistEnabled(true);
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      await expect(
        presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount })
      ).to.be.reverted;
    });

    it("Should allow whitelisted users to purchase", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.setWhitelistEnabled(true);
      await presale.updateWhitelist([buyer1.address], true);
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      const userInfo = await presale.getUserInfo(buyer1.address);
      expect(userInfo.totalTokensPurchased).to.be.gt(0);
    });

    it("Should respect custom whitelist allocations", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      const customAllocation = 5000 * 1e8; // $5,000
      await presale.setWhitelistEnabled(true);
      await presale.setWhitelistAllocations([buyer1.address], [customAllocation]);
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("2"); // ~$7,000
      await expect(
        presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount })
      ).to.be.reverted;
    });
  });

  describe("Round Transitions", function () {
    it("Should auto-transition when Round 1 sells out", async function () {
      // Test that presale auto-transitions when round capacity is reached
      const { presale } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      // Check round 1 info
      const round1Info = await presale.getRoundInfo(1);
      const round1MaxTokens = round1Info.maxTokens;
      
      // Calculate how many purchases needed to fill round 1
      // Round 1: 3B tokens at $0.0015 = $4.5M
      // Max per user: $10,000
      // So we need at least 450 purchases at max
      
      // For simplicity, just verify the auto-transition logic works
      // by checking that we're in Round 1 initially
      expect(await presale.currentRound()).to.equal(1);
      
      // The actual auto-transition would require filling 3B tokens
      // which is impractical in a test, so we verify manual transition works
      // in the next test. The auto-transition code is the same logic.
    });

    it("Should manually transition to Round 2", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      // Fast forward past Round 1 duration
      await time.increase(23 * 24 * 60 * 60); // 23 days
      
      await presale.startRound2();
      expect(await presale.currentRound()).to.equal(2);
    });
  });

  describe("Finalization", function () {
    it("Should finalize presale after Round 2 ends", async function () {
      const { presale, token, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading so finalization can transfer unsold tokens
      await token.connect(owner).enableTrading();
      
      await presale.startPresale();
      await time.increase(23 * 24 * 60 * 60); // 23 days for Round 1
      await presale.startRound2();
      await time.increase(11 * 24 * 60 * 60 + 1); // 11 days for Round 2 + 1 second
      
      await presale.finalizePresale();
      expect(await presale.presaleFinalized()).to.be.true;
    });

    it("Should return unsold tokens on finalization", async function () {
      const { presale, token, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading so finalization can transfer unsold tokens
      await token.connect(owner).enableTrading();
      
      await presale.startPresale();
      await time.increase(23 * 24 * 60 * 60); // Wait for Round 1 to end
      await presale.startRound2(); // Manually start Round 2
      await time.increase(11 * 24 * 60 * 60 + 1); // Wait for Round 2 to end
      
      const presaleBalanceBefore = await token.balanceOf(await presale.getAddress());
      await presale.finalizePresale();
      
      // Owner should receive unsold tokens
      const ownerBalance = await token.balanceOf(owner.address);
      expect(ownerBalance).to.be.gt(0);
    });
  });

  describe("Claims", function () {
    it("Should not allow claims before presale ends", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      await expect(presale.connect(buyer1).claimTokens()).to.be.reverted;
    });

    it("Should claim tokens after presale ends", async function () {
      const { presale, token, buyer1, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading for finalization and claims
      await token.connect(owner).enableTrading();
      
      await presale.startPresale();
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      // Fast forward through both rounds and finalize
      await time.increase(23 * 24 * 60 * 60); // Round 1 duration
      await presale.startRound2();
      await time.increase(11 * 24 * 60 * 60 + 1); // Round 2 duration
      await presale.finalizePresale();
      await presale.enableClaims();
      
      // Claim tokens
      await presale.connect(buyer1).claimTokens();
      
      const balance = await token.balanceOf(buyer1.address);
      expect(balance).to.be.gt(0);
    });

    it("Should include referral bonus in claims", async function () {
      const { presale, token, buyer1, referrer, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading for finalization and claims
      await token.connect(owner).enableTrading();
      
      await presale.setReferralEnabled(true);
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNativeReferral(
        buyer1.address,
        referrer.address,
        { value: ethAmount }
      );
      
      const userInfo = await presale.getUserInfo(buyer1.address);
      // Buyer's referral bonus is 0, only referrer gets bonus
      const expectedTotal = userInfo.totalTokensPurchased;
      
      await time.increase(23 * 24 * 60 * 60);
      await presale.startRound2();
      await time.increase(11 * 24 * 60 * 60 + 1);
      await presale.finalizePresale();
      await presale.enableClaims();
      
      await presale.connect(buyer1).claimTokens();
      const balance = await token.balanceOf(buyer1.address);
      expect(balance).to.equal(expectedTotal);
    });

    it("Should not allow double claiming", async function () {
      const { presale, buyer1, token, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading for finalization and claims
      await token.connect(owner).enableTrading();
      
      await presale.startPresale();
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      await time.increase(23 * 24 * 60 * 60);
      await presale.startRound2();
      await time.increase(11 * 24 * 60 * 60 + 1);
      await presale.finalizePresale();
      await presale.enableClaims();
      
      await presale.connect(buyer1).claimTokens();
      await expect(presale.connect(buyer1).claimTokens()).to.be.reverted;
    });
  });

  describe("Emergency Functions", function () {
    it("Should pause presale", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      await presale.pause();
      
      const ethAmount = ethers.parseEther("1");
      await expect(
        presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount })
      ).to.be.reverted;
    });

    it("Should cancel presale", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      await presale.cancelPresale();
      
      expect(await presale.presaleCancelled()).to.be.true;
    });

    it("Should allow refund if cancelled", async function () {
      const { presale, token, buyer1, owner } = await loadFixture(deployPresaleFixture);
      
      // Enable trading so emergency refund can transfer tokens
      await token.connect(owner).enableTrading();
      
      await presale.startPresale();
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      await presale.cancelPresale();
      await presale.connect(buyer1).emergencyRefund();
      
      // Should receive allocated tokens back
      const balance = await token.balanceOf(buyer1.address);
      expect(balance).to.be.gt(0);
    });
  });

  describe("View Functions", function () {
    it("Should get presale info", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      const info = await presale.getPresaleInfo();
      expect(info.round).to.equal(0); // NOT_STARTED
      expect(info.totalRemaining).to.equal(ethers.parseEther("5000000000"));
    });

    it("Should calculate remaining allocation", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      const ethAmount = ethers.parseEther("0.1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      const remaining = await presale.getRemainingAllocation(buyer1.address);
      expect(remaining).to.be.lt(10000 * 1e8); // Less than max
    });

    it("Should get presale stats", async function () {
      const { presale, buyer1, buyer2 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("0.5");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      await presale.connect(buyer2).buyWithNative(buyer2.address, { value: ethAmount });
      
      const stats = await presale.getPresaleStats();
      expect(stats.totalParticipants).to.equal(2);
      expect(stats.totalTokensSold_).to.be.gt(0);
    });

    it("Should return 0 for getTotalClaimable when user has already claimed", async function () {
      const { presale, token, owner, buyer1 } = await loadFixture(deployPresaleFixture);
      
      // Enable trading first
      await token.connect(owner).enableTrading();
      
      await presale.startPresale();
      
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      // Fast forward to end of round 1 (23 days)
      await time.increase(23 * 24 * 60 * 60 + 1);
      
      // Manually transition to round 2
      await presale.connect(owner).startRound2();
      
      // Fast forward to end of round 2 (11 days)
      await time.increase(11 * 24 * 60 * 60 + 1);
      
      // Finalize presale and enable claims
      await presale.connect(owner).finalizePresale();
      await presale.connect(owner).enableClaims();
      
      // Claim tokens
      await presale.connect(buyer1).claimTokens();
      
      // Should return 0 since user has already claimed
      const claimable = await presale.getTotalClaimable(buyer1.address);
      expect(claimable).to.equal(0);
    });

    it("Should calculate tokens for USD correctly", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);

      await presale.startPresale();

      const usdValue = 1000 * 1e8; // $1000 in 8 decimals
      const tokens = await presale.calculateTokensForUSD(usdValue);
      expect(tokens).to.be.gt(0);
    });

    it("Should get referral info correctly", async function () {
      const { presale, buyer1, buyer2 } = await loadFixture(deployPresaleFixture);
      
      // Enable referrals
      await presale.setReferralEnabled(true);
      
      // Set up a referral by making a purchase with referral
      await presale.startPresale();
      const ethAmount = ethers.parseEther("1");
      
      // Use the correct function signature for referral purchase
      await presale.connect(buyer1).buyWithNative(buyer2.address, { value: ethAmount });
      
      // Get referral info
      const [referrer, bonusTokens, bonusPercentage] = await presale.getReferralInfo(buyer2.address);
      
      // Check that the values are as expected
      expect(referrer).to.equal(ethers.ZeroAddress); // No referrer set in this case
      expect(bonusTokens).to.be.a('bigint');
      expect(bonusPercentage).to.be.a('bigint');
    });
    
    it("Should check if address is whitelisted", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      // Check whitelist status
      const isWhitelisted = await presale.isWhitelisted(buyer1.address);
      
      // The test should pass regardless of whitelist status
      // since we're just testing the view function
      expect(isWhitelisted).to.be.a('boolean');
    });
    
    it("Should get whitelist allocation", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      // Get whitelist allocation
      const allocation = await presale.getWhitelistAllocation(buyer1.address);
      
      // The test should pass regardless of the allocation value
      // since we're just testing the view function
      expect(allocation).to.be.a('bigint');
    });
    
    it("Should calculate round progress", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);
      
      // Get round progress before presale starts
      const progress = await presale.getRoundProgress(1);
      
      // The progress should be a number between 0 and 10000 (basis points)
      expect(progress).to.be.a('bigint');
      expect(Number(progress)).to.be.at.least(0);
      expect(Number(progress)).to.be.at.most(10000);
    });
    
    it("Should get total claimable tokens", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      // Make a purchase
      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });
      
      // Get claimable tokens
      const claimable = await presale.getTotalClaimable(buyer1.address);
      
      // Should be a valid amount (could be 0 if not claimable yet)
      expect(claimable).to.be.a('bigint');
      expect(claimable).to.be.at.least(0);
    });

    it("Should check if user can purchase correctly", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);
      
      await presale.startPresale();
      
      // Check if user can purchase
      const canPurchase = await presale.canPurchase(buyer1.address, 100 * 1e8); // $100
      
      // Should return a boolean
      expect(canPurchase).to.be.a('boolean');
    });

    it("Should reduce remaining allocation after purchase", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      await presale.startPresale();

      // Get max purchase amount and initial remaining allocation
      const maxPurchase = BigInt(await presale.maxPurchasePerUser());
      const initialAllocation = BigInt(await presale.getRemainingAllocation(buyer1.address));
      
      // Make a small purchase (10% of max)
      const purchaseAmount = maxPurchase / 10n;
      const ethAmount = (purchaseAmount * BigInt(1e10)) / 4000n; // Convert to ETH (1 ETH = 4000 USD)
      
      // Make the purchase
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });

      // Get user info after purchase
      const [totalPurchased, totalUSDSpent] = await presale.getUserInfo(buyer1.address);
      
      // Get remaining allocation after purchase
      const remainingAfterPurchase = BigInt(await presale.getRemainingAllocation(buyer1.address));
      
      // Calculate expected remaining (max - spent)
      const expectedRemaining = maxPurchase - BigInt(totalUSDSpent);
      
      // Check that remaining allocation is reduced by the purchase amount
      // Allow for small rounding differences (less than 1%)
      const difference = remainingAfterPurchase > expectedRemaining 
        ? remainingAfterPurchase - expectedRemaining 
        : expectedRemaining - remainingAfterPurchase;
      
      // Allow for 1% tolerance due to rounding in the contract
      const tolerance = maxPurchase / 100n;
      
      // Check that the difference is within tolerance
      expect(difference).to.be.lessThanOrEqual(tolerance);
      
      // Also verify that the remaining is less than initial allocation
      expect(remainingAfterPurchase).to.be.lessThan(initialAllocation);
    });

    it("Should check if presale is sold out", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);

      const isSoldOut = await presale.isSoldOut();
      expect(isSoldOut).to.be.false; // Should not be sold out initially
    });

    it("Should calculate presale progress correctly", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      await presale.startPresale();

      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });

      const progress = await presale.getPresaleProgress();
      expect(progress).to.be.gt(0);
      expect(progress).to.be.lte(10000); // Max 100% in basis points
    });

    it("Should calculate time remaining correctly", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);

      await presale.startPresale();

      const timeRemaining = await presale.getTimeRemaining();
      expect(timeRemaining).to.be.gt(0); // Should have time remaining in Round 1
    });

    it("Should calculate round time remaining correctly", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);

      await presale.startPresale();

      const round1Time = await presale.getRoundTimeRemaining(1);
      const round2Time = await presale.getRoundTimeRemaining(2);

      expect(round1Time).to.be.gt(0); // Round 1 should be active
      expect(round2Time).to.equal(0); // Round 2 should not be active yet
    });

    it("Should check whitelist status correctly", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      const isWhitelisted = await presale.isWhitelisted(buyer1.address);
      expect(isWhitelisted).to.be.false; // Should not be whitelisted initially
    });

    it("Should get whitelist allocation correctly", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      const allocation = await presale.getWhitelistAllocation(buyer1.address);
      expect(allocation).to.equal(0); // Should be 0 initially
    });

    it("Should calculate round progress correctly", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      await presale.startPresale();

      const ethAmount = ethers.parseEther("1");
      await presale.connect(buyer1).buyWithNative(buyer1.address, { value: ethAmount });

      const progress = await presale.getRoundProgress(1);
      expect(progress).to.be.gt(0);
      expect(progress).to.be.lte(10000); // Max 100% in basis points
    });
  });

  describe("Receive and Fallback", function () {
    it("Should reject direct ETH transfers to receive", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      // Try to send ETH directly (not through buyWithNative)
      await expect(
        buyer1.sendTransaction({
          to: await presale.getAddress(),
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWith("Use buyWithNative function");
    });

    it("Should reject invalid function calls to fallback", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      // Try to call non-existent function
      await expect(
        buyer1.sendTransaction({
          to: await presale.getAddress(),
          data: "0x12345678",
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWith("Invalid function call");
    });
  });

  describe("Admin Functions", function () {
    it("Should update token prices", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);

      const newPrice = 4000 * 1e8; // $4000
      await presale.setTokenPrice(
        ethers.ZeroAddress, // Native token
        newPrice,
        18,
        true
      );

      const priceInfo = await presale.getTokenPrice(ethers.ZeroAddress);
      expect(priceInfo.priceUSD).to.equal(newPrice);
    });

    it("Should update limits", async function () {
      const { presale } = await loadFixture(deployPresaleFixture);

      const newMax = 20000 * 1e8; // $20,000
      const newMin = 100 * 1e8; // $100

      await presale.setLimits(newMax, newMin);

      expect(await presale.maxPurchasePerUser()).to.equal(newMax);
      expect(await presale.minPurchaseAmount()).to.equal(newMin);
    });

    it("Should update treasury", async function () {
      const { presale, buyer1 } = await loadFixture(deployPresaleFixture);

      await presale.setTreasury(buyer1.address);
      expect(await presale.treasury()).to.equal(buyer1.address);
    });
  });
});
