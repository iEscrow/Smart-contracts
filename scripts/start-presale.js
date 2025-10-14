const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Starting iEscrow Presale...\n");

    // Configuration
    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";

    if (presaleAddress === "YOUR_PRESALE_ADDRESS") {
        console.error("❌ Error: Please set PRESALE_ADDRESS in environment");
        process.exit(1);
    }

    // Get contract instance
    const presale = await ethers.getContractAt("iEscrowPresale", presaleAddress);
    console.log("Presale Contract:", presaleAddress);

    // Get signer
    const [signer] = await ethers.getSigners();
    console.log("Starting with account:", signer.address);
    console.log("");

    // Pre-flight checks
    console.log("🔍 Pre-flight Checks...\n");

    // Check rounds are configured
    const round1Info = await presale.getRoundInfo(1);
    const round2Info = await presale.getRoundInfo(2);

    console.log("Round 1:");
    console.log("  Price:", ethers.utils.formatUnits(round1Info.tokenPrice, 8), "USD");
    console.log("  Max Tokens:", ethers.utils.formatEther(round1Info.maxTokens));

    console.log("\nRound 2:");
    console.log("  Price:", ethers.utils.formatUnits(round2Info.tokenPrice, 8), "USD");
    console.log("  Max Tokens:", ethers.utils.formatEther(round2Info.maxTokens));

    if (round1Info.tokenPrice.eq(0) || round2Info.tokenPrice.eq(0)) {
        console.error("\n❌ Error: Rounds not configured properly");
        process.exit(1);
    }

    // Check token balance
    const escrowTokenAddress = await presale.escrowToken();
    const escrowToken = await ethers.getContractAt("IERC20", escrowTokenAddress);
    const presaleBalance = await escrowToken.balanceOf(presaleAddress);

    console.log("\n💰 Token Balance:");
    console.log("  Presale balance:", ethers.utils.formatEther(presaleBalance), "$ESCROW");
    console.log("  Required:", "5,000,000,000 $ESCROW");

    const requiredBalance = ethers.utils.parseEther("5000000000");
    if (presaleBalance.lt(requiredBalance)) {
        console.error("\n❌ Error: Insufficient token balance in presale contract");
        console.error("Please run transfer-tokens.js first");
        process.exit(1);
    }

    console.log("\n✅ All checks passed!");

    // Start presale
    console.log("\n🚀 Starting Presale (Round 1)...");

    const tx = await presale.startPresale();
    console.log("Transaction hash:", tx.hash);

    console.log("⏳ Waiting for confirmation...");
    await tx.wait();

    console.log("✅ Presale started successfully!");

    // Get presale info
    const presaleInfo = await presale.getPresaleInfo();
    const currentRound = presaleInfo.round;

    console.log("\n📊 Presale Status:");
    console.log("  Round:", currentRound === 1 ? "Round 1" : "Not Started");
    console.log("  Start Time:", new Date().toISOString());
    console.log("  Total Tokens:", ethers.utils.formatEther(presaleInfo.totalRemaining));
    console.log("  Is Active:", presaleInfo.isActive);

    console.log("\n🎉 Presale is now LIVE!");
    console.log("\n📝 What's Next:");
    console.log("1. Monitor presale progress with monitor-presale.js");
    console.log("2. Users can now purchase tokens");
    console.log("3. Round 1 will last 23 days or until sold out");
    console.log("4. After Round 1, start Round 2 with start-round2.js");
    console.log("");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
