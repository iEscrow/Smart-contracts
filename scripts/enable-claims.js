const { ethers } = require("hardhat");

async function main() {
    console.log("🎁 Enabling Token Claims...\n");

    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";

    if (presaleAddress === "YOUR_PRESALE_ADDRESS") {
        console.error("❌ Error: Please set PRESALE_ADDRESS in environment");
        process.exit(1);
    }

    const presale = await ethers.getContractAt("iEscrowPresale", presaleAddress);

    // Check presale is finalized
    const presaleInfo = await presale.getPresaleInfo();

    if (!presaleInfo.isFinalized) {
        console.error("❌ Error: Presale must be finalized first");
        console.error("Run finalize-presale.js first");
        process.exit(1);
    }

    console.log("✅ Presale is finalized");
    console.log("Enabling claims...\n");

    const tx = await presale.enableClaims();
    console.log("Transaction hash:", tx.hash);

    console.log("⏳ Waiting for confirmation...");
    await tx.wait();

    console.log("✅ Claims enabled successfully!");
    console.log("\n📊 TGE (Token Generation Event) is now LIVE!");
    console.log("Users can now claim their tokens");
    console.log("");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
