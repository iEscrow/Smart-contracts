const { ethers } = require("hardhat");

async function main() {
    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";
    const userAddress = process.argv[2] || process.env.USER_ADDRESS;

    if (!userAddress) {
        console.error("❌ Usage: node scripts/check-user.js <USER_ADDRESS>");
        process.exit(1);
    }

    console.log("👤 Checking User Information\n");
    console.log("Presale:", presaleAddress);
    console.log("User:", userAddress);
    console.log("");

    const presale = await ethers.getContractAt("iEscrowPresale", presaleAddress);

    // Get user info
    const userInfo = await presale.getUserInfo(userAddress);

    console.log("📊 User Details:");
    console.log("-".repeat(60));
    console.log("Total Tokens Purchased:", ethers.utils.formatEther(userInfo.totalTokensPurchased), "$ESCROW");
    console.log("Total USD Spent:", "$" + ethers.utils.formatUnits(userInfo.totalUSDSpent, 8));
    console.log("Round 1 Purchased:", ethers.utils.formatEther(userInfo.round1Purchased), "$ESCROW");
    console.log("Round 2 Purchased:", ethers.utils.formatEther(userInfo.round2Purchased), "$ESCROW");
    console.log("Referral Bonus:", ethers.utils.formatEther(userInfo.referralBonusAmount), "$ESCROW");
    console.log("Has Claimed:", userInfo.hasClaimed ? "Yes" : "No");
    console.log("Is Whitelisted:", userInfo.isWhitelisted ? "Yes" : "No");

    // Get remaining allocation
    const remaining = await presale.getRemainingAllocation(userAddress);
    console.log("\nRemaining Allocation:", "$" + ethers.utils.formatUnits(remaining, 8));

    // Get referral info
    const referralInfo = await presale.getReferralInfo(userAddress);
    if (referralInfo.referrerAddress !== ethers.constants.AddressZero) {
        console.log("\n🎁 Referral Info:");
        console.log("Referrer:", referralInfo.referrerAddress);
        console.log("Bonus Tokens:", ethers.utils.formatEther(referralInfo.bonusTokens));
        console.log("Bonus Percentage:", (referralInfo.bonusPercentage.toNumber() / 100) + "%");
    }

    // Get total claimable
    const claimable = await presale.getTotalClaimable(userAddress);
    console.log("\n💰 Total Claimable:", ethers.utils.formatEther(claimable), "$ESCROW");

    console.log("");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
