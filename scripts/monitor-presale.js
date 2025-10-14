const { ethers } = require("hardhat");

async function main() {
    console.log("📊 iEscrow Presale Monitor\n");
    console.log("=".repeat(60));

    // Configuration
    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";

    if (presaleAddress === "YOUR_PRESALE_ADDRESS") {
        console.error("❌ Error: Please set PRESALE_ADDRESS in environment");
        process.exit(1);
    }

    // Get contract instance
    const presale = await ethers.getContractAt("iEscrowPresale", presaleAddress);

    // Get presale info
    const presaleInfo = await presale.getPresaleInfo();
    const presaleStats = await presale.getPresaleStats();
    const round1Info = await presale.getRoundInfo(1);
    const round2Info = await presale.getRoundInfo(2);

    // Format round name
    const roundNames = ["Not Started", "Round 1", "Round 2", "Ended"];
    const currentRound = roundNames[presaleInfo.round];

    // Display General Info
    console.log("\n📋 PRESALE OVERVIEW");
    console.log("-".repeat(60));
    console.log("Contract:", presaleAddress);
    console.log("Current Round:", currentRound);
    console.log("Status:", presaleInfo.isActive ? "🟢 ACTIVE" : "🔴 INACTIVE");
    console.log("Finalized:", presaleInfo.isFinalized ? "Yes" : "No");
    console.log("Cancelled:", presaleInfo.isCancelled ? "Yes" : "No");

    // Display Statistics
    console.log("\n📈 STATISTICS");
    console.log("-".repeat(60));
    console.log("Total Participants:", presaleStats.totalParticipants.toString());
    console.log("Total Tokens Sold:", ethers.utils.formatEther(presaleStats.totalTokensSold_), "$ESCROW");
    console.log("Total USD Raised:", "$" + ethers.utils.formatUnits(presaleStats.totalUSDRaised_, 8));
    console.log("Progress:", (presaleStats.percentComplete.toNumber() / 100).toFixed(2) + "%");

    // Display Round 1 Info
    console.log("\n💎 ROUND 1");
    console.log("-".repeat(60));
    console.log("Price:", "$" + ethers.utils.formatUnits(round1Info.tokenPrice, 8));
    console.log("Duration:", (round1Info.duration.toNumber() / 86400).toFixed(0), "days");
    console.log("Max Tokens:", ethers.utils.formatEther(round1Info.maxTokens));
    console.log("Sold:", ethers.utils.formatEther(round1Info.tokensSold));
    console.log("Remaining:", ethers.utils.formatEther(round1Info.tokensRemaining));
    console.log("Progress:", (round1Info.tokensSold.mul(10000).div(round1Info.maxTokens).toNumber() / 100).toFixed(2) + "%");

    if (round1Info.startTime.gt(0)) {
        const startDate = new Date(round1Info.startTime.toNumber() * 1000);
        const endDate = new Date(round1Info.endTime.toNumber() * 1000);
        console.log("Start Time:", startDate.toLocaleString());
        console.log("End Time:", endDate.toLocaleString());

        if (round1Info.isActive) {
            const timeRemaining = round1Info.endTime.toNumber() - Math.floor(Date.now() / 1000);
            if (timeRemaining > 0) {
                const days = Math.floor(timeRemaining / 86400);
                const hours = Math.floor((timeRemaining % 86400) / 3600);
                const minutes = Math.floor((timeRemaining % 3600) / 60);
                console.log("Time Remaining:", `${days}d ${hours}h ${minutes}m`);
            }
        }
    }

    // Display Round 2 Info
    console.log("\n💎 ROUND 2");
    console.log("-".repeat(60));
    console.log("Price:", "$" + ethers.utils.formatUnits(round2Info.tokenPrice, 8));
    console.log("Duration:", (round2Info.duration.toNumber() / 86400).toFixed(0), "days");
    console.log("Max Tokens:", ethers.utils.formatEther(round2Info.maxTokens));
    console.log("Sold:", ethers.utils.formatEther(round2Info.tokensSold));
    console.log("Remaining:", ethers.utils.formatEther(round2Info.tokensRemaining));

    if (round2Info.maxTokens.gt(0)) {
        console.log("Progress:", (round2Info.tokensSold.mul(10000).div(round2Info.maxTokens).toNumber() / 100).toFixed(2) + "%");
    }

    if (round2Info.startTime.gt(0)) {
        const startDate = new Date(round2Info.startTime.toNumber() * 1000);
        const endDate = new Date(round2Info.endTime.toNumber() * 1000);
        console.log("Start Time:", startDate.toLocaleString());
        console.log("End Time:", endDate.toLocaleString());

        if (round2Info.isActive) {
            const timeRemaining = round2Info.endTime.toNumber() - Math.floor(Date.now() / 1000);
            if (timeRemaining > 0) {
                const days = Math.floor(timeRemaining / 86400);
                const hours = Math.floor((timeRemaining % 86400) / 3600);
                const minutes = Math.floor((timeRemaining % 3600) / 60);
                console.log("Time Remaining:", `${days}d ${hours}h ${minutes}m`);
            }
        }
    }

    // Display Payment Tokens
    console.log("\n💰 ACCEPTED PAYMENT TOKENS");
    console.log("-".repeat(60));

    const tokenAddresses = [
        { name: "ETH", address: "0x0000000000000000000000000000000000000000" },
        { name: "WETH", address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" },
        { name: "WBNB", address: "0x418D75f65a02b3D53B2418FB8E1fe493759c7605" },
        { name: "LINK", address: "0x514910771AF9Ca656af840dff83E8264EcF986CA" },
        { name: "WBTC", address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599" },
        { name: "USDC", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" },
        { name: "USDT", address: "0xdAC17F958D2ee523a2206206994597C13D831ec7" },
    ];

    for (const token of tokenAddresses) {
        try {
            const tokenPrice = await presale.getTokenPrice(token.address);
            if (tokenPrice.isActive) {
                console.log(`${token.name}: $${ethers.utils.formatUnits(tokenPrice.priceUSD, 8)}`);
            }
        } catch (error) {
            // Skip if error
        }
    }

    console.log("\n" + "=".repeat(60));
    console.log("✅ Monitor complete\n");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
