const hre = require("hardhat");

async function main() {
  console.log("🚀 Starting iEscrow Local Deployment...\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString(), "\n");

  // Deploy EscrowToken
  console.log("📝 Deploying EscrowToken...");
  const EscrowToken = await hre.ethers.getContractFactory("EscrowToken");
  const escrowToken = await EscrowToken.deploy(deployer.address);
  await escrowToken.waitForDeployment();
  const tokenAddress = await escrowToken.getAddress();
  console.log("✅ EscrowToken deployed to:", tokenAddress);

  // Deploy EscrowPresale
  console.log("\n📝 Deploying iEscrowPresale...");
  const EscrowPresale = await hre.ethers.getContractFactory("iEscrowPresale");
  const escrowPresale = await EscrowPresale.deploy(
    tokenAddress,
    deployer.address // treasury
  );
  await escrowPresale.waitForDeployment();
  const presaleAddress = await escrowPresale.getAddress();
  console.log("✅ EscrowPresale deployed to:", presaleAddress);

  // Grant MINTER_ROLE to presale
  console.log("\n🔑 Granting MINTER_ROLE to Presale contract...");
  const MINTER_ROLE = await escrowToken.MINTER_ROLE();
  await escrowToken.grantRole(MINTER_ROLE, presaleAddress);
  console.log("✅ MINTER_ROLE granted");

  // Mint tokens to presale contract
  console.log("\n💰 Minting tokens to Presale contract...");
  const presaleAmount = hre.ethers.parseEther("5000000000"); // 5 billion tokens
  await escrowToken.mint(presaleAddress, presaleAmount);
  console.log("✅ Minted 5,000,000,000 tokens to Presale");

  // Configure Round 1
  console.log("\n⚙️  Configuring Round 1...");
  const round1Price = 150000; // $0.0015 (8 decimals)
  const round1Tokens = hre.ethers.parseEther("3000000000"); // 3 billion
  await escrowPresale.configureRound(1, round1Price, round1Tokens);
  console.log("✅ Round 1 configured: $0.0015, 3B tokens");

  // Configure Round 2
  console.log("\n⚙️  Configuring Round 2...");
  const round2Price = 200000; // $0.002 (8 decimals)
  const round2Tokens = hre.ethers.parseEther("2000000000"); // 2 billion
  await escrowPresale.configureRound(2, round2Price, round2Tokens);
  console.log("✅ Round 2 configured: $0.002, 2B tokens");

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("📊 DEPLOYMENT SUMMARY");
  console.log("=".repeat(60));
  console.log("EscrowToken:", tokenAddress);
  console.log("EscrowPresale:", presaleAddress);
  console.log("Deployer:", deployer.address);
  console.log("Treasury:", deployer.address);
  console.log("\n✅ All contracts deployed successfully!");
  console.log("\n📝 Next Steps:");
  console.log("1. Start presale: await presale.startPresale()");
  console.log("2. Enable trading: await token.enableTrading()");
  console.log("3. Test purchases with buyWithNative()");
  console.log("=".repeat(60));

  // Save deployment info
  const fs = require("fs");
  const deploymentInfo = {
    network: hre.network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      EscrowToken: tokenAddress,
      EscrowPresale: presaleAddress,
    },
    config: {
      round1: {
        price: "$0.0015",
        tokens: "3,000,000,000",
      },
      round2: {
        price: "$0.002",
        tokens: "2,000,000,000",
      },
    },
  };

  fs.writeFileSync(
    "deployment-local.json",
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log("\n💾 Deployment info saved to deployment-local.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
