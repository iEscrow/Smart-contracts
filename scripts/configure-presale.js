const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    console.log("🔧 Configuring iEscrow Presale...\n");

    // Presale contract address (update this after deployment)
    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";

    if (presaleAddress === "YOUR_PRESALE_ADDRESS") {
        console.error("❌ Error: Please set PRESALE_ADDRESS in environment");
        process.exit(1);
    }

    // Get contract instance
    const presale = await ethers.getContractAt("iEscrowPresale", presaleAddress);
    console.log("Connected to Presale:", presaleAddress);

    // Get signer
    const [signer] = await ethers.getSigners();
    console.log("Configuring with account:", signer.address);
    console.log("");

    // ============ ROUND CONFIGURATION ============
    console.log("📝 Configuring Rounds...\n");

    // Round 1: 3 billion tokens at $0.0015
    const round1Price = ethers.utils.parseUnits("0.0015", 8); // 8 decimals for USD
    const round1Tokens = ethers.utils.parseEther("3000000000"); // 3 billion tokens

    console.log("Round 1:");
    console.log("  Price: $0.0015 per token");
    console.log("  Tokens:", ethers.utils.formatEther(round1Tokens));

    let tx = await presale.configureRound(1, round1Price, round1Tokens);
    await tx.wait();
    console.log("✅ Round 1 configured\n");

    // Round 2: 2 billion tokens at $0.002
    const round2Price = ethers.utils.parseUnits("0.002", 8);
    const round2Tokens = ethers.utils.parseEther("2000000000"); // 2 billion tokens

    console.log("Round 2:");
    console.log("  Price: $0.002 per token");
    console.log("  Tokens:", ethers.utils.formatEther(round2Tokens));

    tx = await presale.configureRound(2, round2Price, round2Tokens);
    await tx.wait();
    console.log("✅ Round 2 configured\n");

    // ============ TOKEN PRICE UPDATES ============
    console.log("💰 Updating Token Prices...\n");

    // Update prices for payment tokens (example prices)
    const tokenUpdates = [
        { name: "ETH", address: "0x0000000000000000000000000000000000000000", price: "3500", decimals: 18 },
        { name: "WETH", address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", price: "3500", decimals: 18 },
        { name: "WBNB", address: "0x418D75f65a02b3D53B2418FB8E1fe493759c7605", price: "600", decimals: 18 },
        { name: "LINK", address: "0x514910771AF9Ca656af840dff83E8264EcF986CA", price: "15", decimals: 18 },
        { name: "WBTC", address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", price: "95000", decimals: 8 },
        { name: "USDC", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", price: "1", decimals: 6 },
        { name: "USDT", address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", price: "1", decimals: 6 },
    ];

    for (const token of tokenUpdates) {
        const priceUSD = ethers.utils.parseUnits(token.price, 8);
        tx = await presale.setTokenPrice(token.address, priceUSD, token.decimals, true);
        await tx.wait();
        console.log(`✅ ${token.name}: $${token.price}`);
    }
    console.log("");

    // ============ LIMITS CONFIGURATION ============
    console.log("⚙️  Setting Purchase Limits...\n");

    const maxPurchase = ethers.utils.parseUnits("10000", 8); // $10,000 max per user
    const minPurchase = ethers.utils.parseUnits("50", 8);    // $50 minimum

    tx = await presale.setLimits(maxPurchase, minPurchase);
    await tx.wait();
    console.log("✅ Limits set:");
    console.log("  Max per user: $10,000");
    console.log("  Minimum: $50");
    console.log("");

    // ============ REFERRAL SYSTEM ============
    console.log("🎁 Enabling Referral System...\n");

    tx = await presale.setReferralEnabled(true);
    await tx.wait();
    console.log("✅ Referral system enabled (5% bonus)");
    console.log("");

    // ============ VERIFICATION ============
    console.log("🔍 Verifying Configuration...\n");

    const round1Info = await presale.getRoundInfo(1);
    const round2Info = await presale.getRoundInfo(2);

    console.log("Round 1:");
    console.log("  Token Price:", ethers.utils.formatUnits(round1Info.tokenPrice, 8), "USD");
    console.log("  Max Tokens:", ethers.utils.formatEther(round1Info.maxTokens));
    console.log("  Duration:", round1Info.duration.toString(), "seconds");

    console.log("\nRound 2:");
    console.log("  Token Price:", ethers.utils.formatUnits(round2Info.tokenPrice, 8), "USD");
    console.log("  Max Tokens:", ethers.utils.formatEther(round2Info.maxTokens));
    console.log("  Duration:", round2Info.duration.toString(), "seconds");

    console.log("\n✅ Configuration Complete!");
    console.log("\n📝 Next Steps:");
    console.log("1. Transfer 5 billion $ESCROW tokens to presale contract");
    console.log("2. Run start-presale.js to begin the presale");
    console.log("");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
