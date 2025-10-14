const { ethers } = require("hardhat");

async function main() {
    console.log("🏁 Finalizing iEscrow Presale...\n");

    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";

    if (presaleAddress === "YOUR_PRESALE_ADDRESS") {
        console.error("❌ Error: Please set PRESALE_ADDRESS in environment");
        process.exit(1);
    }

    const presale = await ethers.getContractAt("iEscrowPresale", presaleAddress);

    // Check presale status
    const presaleInfo = await presale.getPresaleInfo();
    const round2Info = await presale.getRoundInfo(2);

    console.log("📊 Current Status:");
    console.log("Round:", presaleInfo.round === 2 ? "Round 2" : "Other");
    console.log("Total Sold:", ethers.utils.formatEther(presaleInfo.totalSold));
    console.log("Is Finalized:", presaleInfo.isFinalized);
    console.log("");

    // Check if Round 2 has ended
    const now = Math.floor(Date.now() / 1000);
    const round2Ended = round2Info.endTime.gt(0) && now >= round2Info.endTime.toNumber();

    if (!round2Ended && !presaleInfo.round === 3) {
        console.error("❌ Error: Round 2 has not ended yet");
        const remaining = round2Info.endTime.toNumber() - now;
        const days = Math.floor(remaining / 86400);
        const hours = Math.floor((remaining % 86400) / 3600);
        console.error(`Time remaining: ${days}d ${hours}h`);
        process.exit(1);
    }

    console.log("✅ Presale has ended");
    console.log("Finalizing...\n");

    const tx = await presale.finalizePresale();
    console.log("Transaction hash:", tx.hash);

    console.log("⏳ Waiting for confirmation...");
    await tx.wait();

    console.log("✅ Presale finalized successfully!");

    // Get final stats
    const stats = await presale.getPresaleStats();

    console.log("\n📊 Final Statistics:");
    console.log("-".repeat(60));
    console.log("Total Participants:", stats.totalParticipants.toString());
    console.log("Total Tokens Sold:", ethers.utils.formatEther(stats.totalTokensSold_), "$ESCROW");
    console.log("Total USD Raised:", "$" + ethers.utils.formatUnits(stats.totalUSDRaised_, 8));
    console.log("Round 1 Sold:", ethers.utils.formatEther(stats.round1Sold), "$ESCROW");
    console.log("Round 2 Sold:", ethers.utils.formatEther(stats.round2Sold), "$ESCROW");
    console.log("Completion:", (stats.percentComplete.toNumber() / 100).toFixed(2) + "%");

    console.log("\n📝 Next Steps:");
    console.log("1. Run enable-claims.js to allow users to claim tokens");
    console.log("2. Monitor claims");
    console.log("3. Withdraw funds to treasury");
    console.log("");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
