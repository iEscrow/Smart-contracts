const { ethers } = require("hardhat");

async function main() {
    console.log("💰 Transferring $ESCROW Tokens to Presale Contract...\n");

    // Configuration
    const escrowTokenAddress = process.env.ESCROW_TOKEN_ADDRESS || "YOUR_ESCROW_TOKEN_ADDRESS";
    const presaleAddress = process.env.PRESALE_ADDRESS || "YOUR_PRESALE_ADDRESS";

    if (escrowTokenAddress === "YOUR_ESCROW_TOKEN_ADDRESS" || presaleAddress === "YOUR_PRESALE_ADDRESS") {
        console.error("❌ Error: Please set ESCROW_TOKEN_ADDRESS and PRESALE_ADDRESS in environment");
        process.exit(1);
    }

    console.log("Configuration:");
    console.log("  Escrow Token:", escrowTokenAddress);
    console.log("  Presale:", presaleAddress);
    console.log("");

    // Get signer
    const [signer] = await ethers.getSigners();
    console.log("Transfer from:", signer.address);

    // Get token contract
    const escrowToken = await ethers.getContractAt("IERC20", escrowTokenAddress);

    // Check balance
    const balance = await escrowToken.balanceOf(signer.address);
    console.log("Current balance:", ethers.utils.formatEther(balance), "$ESCROW");

    // Amount to transfer: 5 billion tokens
    const amount = ethers.utils.parseEther("5000000000"); // 5 billion tokens
    console.log("Transfer amount:", ethers.utils.formatEther(amount), "$ESCROW");

    if (balance.lt(amount)) {
        console.error("❌ Error: Insufficient token balance");
        process.exit(1);
    }

    console.log("\n🔄 Transferring tokens...");

    // Execute transfer
    const tx = await escrowToken.transfer(presaleAddress, amount);
    console.log("Transaction hash:", tx.hash);

    console.log("⏳ Waiting for confirmation...");
    await tx.wait();

    console.log("✅ Tokens transferred successfully!");

    // Verify
    const presaleBalance = await escrowToken.balanceOf(presaleAddress);
    console.log("\n🔍 Verification:");
    console.log("  Presale balance:", ethers.utils.formatEther(presaleBalance), "$ESCROW");

    console.log("\n✅ Transfer Complete!");
    console.log("\n📝 Next Step:");
    console.log("Run start-presale.js to begin the presale");
    console.log("");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
