const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Deploying iEscrow Presale Contract...\n");

    // Configuration - Load from environment
    const config = {
        escrowToken: process.env.ESCROW_TOKEN_ADDRESS || "0x0000000000000000000000000000000000000000",
        treasury: process.env.TREASURY_ADDRESS || "0x0000000000000000000000000000000000000000",
    };

    console.log("Configuration:");
    console.log("  Escrow Token:", config.escrowToken);
    console.log("  Treasury:", config.treasury);
    console.log("");

    // Validate addresses
    if (config.escrowToken === "0x0000000000000000000000000000000000000000") {
        console.error("❌ Error: ESCROW_TOKEN_ADDRESS not set in environment");
        process.exit(1);
    }

    if (config.treasury === "0x0000000000000000000000000000000000000000") {
        console.error("❌ Error: TREASURY_ADDRESS not set in environment");
        process.exit(1);
    }

    // Get deployer account
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

    // Deploy Presale Contract
    console.log("📝 Deploying iEscrowPresale...");
    const iEscrowPresale = await ethers.getContractFactory("iEscrowPresale");
    const presale = await iEscrowPresale.deploy(
        config.escrowToken,
        config.treasury
    );

    await presale.deployed();
    console.log("✅ Presale Contract Deployed:", presale.address);

    // Display deployment info
    console.log("\n📋 Deployment Summary:");
    console.log("  Presale Address:", presale.address);
    console.log("  Escrow Token:", config.escrowToken);
    console.log("  Treasury:", config.treasury);
    console.log("  Network:", hre.network.name);
    console.log("");

    // Verify contract info
    console.log("🔍 Verifying Deployment...");
    const escrowTokenAddr = await presale.escrowToken();
    const treasuryAddr = await presale.treasury();
    const totalPresaleTokens = await presale.TOTAL_PRESALE_TOKENS();

    console.log("  Escrow Token:", escrowTokenAddr);
    console.log("  Treasury:", treasuryAddr);
    console.log("  Total Presale Tokens:", ethers.utils.formatEther(totalPresaleTokens));
    console.log("");

    // Save deployment info
    const deploymentInfo = {
        network: hre.network.name,
        presaleAddress: presale.address,
        escrowToken: config.escrowToken,
        treasury: config.treasury,
        deployer: deployer.address,
        deploymentTime: new Date().toISOString(),
        totalPresaleTokens: ethers.utils.formatEther(totalPresaleTokens),
    };

    console.log("💾 Deployment Info:");
    console.log(JSON.stringify(deploymentInfo, null, 2));
    console.log("");

    // Next steps
    console.log("📝 Next Steps:");
    console.log("1. Configure rounds with configureRound()");
    console.log("2. Set token prices with setTokenPrice()");
    console.log("3. Transfer 5 billion $ESCROW tokens to presale contract");
    console.log("4. Start presale with startPresale()");
    console.log("");

    if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
        console.log("⏳ Waiting for block confirmations...");
        await presale.deployTransaction.wait(5);

        console.log("🔍 Verifying contract on Etherscan...");
        try {
            await hre.run("verify:verify", {
                address: presale.address,
                constructorArguments: [config.escrowToken, config.treasury],
            });
            console.log("✅ Contract verified on Etherscan");
        } catch (error) {
            console.log("⚠️  Verification failed:", error.message);
        }
    }

    console.log("\n✅ Deployment Complete!\n");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
