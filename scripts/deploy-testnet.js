const hre = require("hardhat");
const fs = require("fs");

async function main() {
  console.log("🚀 Starting iEscrow Testnet Deployment...\n");
  console.log("Network:", hre.network.name);

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "ETH\n");

  // Deployment configuration
  const config = {
    presaleRate: 666666666666666666n, // ~666.67 tokens per dollar
    maxTokensToSell: hre.ethers.parseEther("5000000000"), // 5 billion
    round1Price: 150000, // $0.0015 (8 decimals)
    round1Tokens: hre.ethers.parseEther("3000000000"), // 3 billion
    round2Price: 200000, // $0.002 (8 decimals)
    round2Tokens: hre.ethers.parseEther("2000000000"), // 2 billion
  };

  console.log("=".repeat(60));
  console.log("DEPLOYMENT CONFIGURATION");
  console.log("=".repeat(60));
  console.log("Presale Rate:", config.presaleRate.toString());
  console.log("Max Tokens:", hre.ethers.formatEther(config.maxTokensToSell));
  console.log("Round 1 Price: $0.0015");
  console.log("Round 2 Price: $0.002");
  console.log("=".repeat(60) + "\n");

  // Step 1: Deploy EscrowToken
  console.log("📝 Step 1/4: Deploying EscrowToken...");
  const EscrowToken = await hre.ethers.getContractFactory("EscrowToken");
  const escrowToken = await EscrowToken.deploy(deployer.address);
  await escrowToken.waitForDeployment();
  const tokenAddress = await escrowToken.getAddress();
  console.log("✅ EscrowToken deployed:", tokenAddress);

  // Step 2: Deploy EscrowPresale
  console.log("\n📝 Step 2/4: Deploying EscrowPresale...");
  const EscrowPresale = await hre.ethers.getContractFactory("EscrowPresale");
  const escrowPresale = await EscrowPresale.deploy(
    tokenAddress,
    deployer.address // treasury
  );
  await escrowPresale.waitForDeployment();
  const presaleAddress = await escrowPresale.getAddress();
  console.log("✅ EscrowPresale deployed:", presaleAddress);

  // Step 3: Deploy EscrowStaking
  console.log("\n📝 Step 3/4: Deploying EscrowStaking...");
  const EscrowStaking = await hre.ethers.getContractFactory("EscrowStaking");
  const escrowStaking = await EscrowStaking.deploy(
    tokenAddress,
    deployer.address // treasury
  );
  await escrowStaking.waitForDeployment();
  const stakingAddress = await escrowStaking.getAddress();
  console.log("✅ EscrowStaking deployed:", stakingAddress);

  // Step 4: Configuration
  console.log("\n📝 Step 4/4: Configuring contracts...");

  // Grant roles
  console.log("- Granting MINTER_ROLE to Presale...");
  const minterRole = await escrowToken.MINTER_ROLE();
  await escrowToken.grantRole(minterRole, presaleAddress);
  
  console.log("- Granting MINTER_ROLE to Staking...");
  await escrowToken.grantRole(minterRole, stakingAddress);

  // Mint tokens to presale
  console.log("- Minting tokens to Presale...");
  await escrowToken.mint(presaleAddress, config.maxTokensToSell);

  // Mint tokens to staking (for rewards pool)
  console.log("- Minting tokens to Staking...");
  const stakingSupply = hre.ethers.parseEther("10000000000"); // 10 billion for rewards
  await escrowToken.mint(stakingAddress, stakingSupply);

  // Configure presale rounds
  console.log("- Configuring Round 1...");
  await escrowPresale.configureRound(1, config.round1Price, config.round1Tokens);
  
  console.log("- Configuring Round 2...");
  await escrowPresale.configureRound(2, config.round2Price, config.round2Tokens);

  console.log("✅ Configuration complete");

  // Deployment summary
  console.log("\n" + "=".repeat(60));
  console.log("📊 DEPLOYMENT SUMMARY");
  console.log("=".repeat(60));
  console.log("Network:", hre.network.name);
  console.log("Deployer:", deployer.address);
  console.log("Treasury:", deployer.address);
  console.log("\nContract Addresses:");
  console.log("  EscrowToken:   ", tokenAddress);
  console.log("  EscrowPresale: ", presaleAddress);
  console.log("  EscrowStaking: ", stakingAddress);
  console.log("\nToken Allocation:");
  console.log("  Presale:  ", hre.ethers.formatEther(config.maxTokensToSell), "tokens");
  console.log("  Staking:  ", hre.ethers.formatEther(stakingSupply), "tokens");
  console.log("\nPresale Configuration:");
  console.log("  Round 1: $0.0015/token, 3B tokens, 23 days");
  console.log("  Round 2: $0.002/token, 2B tokens, 11 days");
  console.log("=".repeat(60));

  // Save deployment info
  const deploymentInfo = {
    network: hre.network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      EscrowToken: tokenAddress,
      EscrowPresale: presaleAddress,
      EscrowStaking: stakingAddress,
    },
    config: {
      presaleRate: config.presaleRate.toString(),
      maxTokensToSell: hre.ethers.formatEther(config.maxTokensToSell),
      stakingSupply: hre.ethers.formatEther(stakingSupply),
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

  const filename = `deployment-${hre.network.name}.json`;
  fs.writeFileSync(filename, JSON.stringify(deploymentInfo, null, 2));
  console.log("\n💾 Deployment info saved to:", filename);

  // Verification instructions
  console.log("\n📝 Next Steps:");
  console.log("1. Verify contracts on Etherscan:");
  console.log(`   npx hardhat verify --network ${hre.network.name} ${tokenAddress} ${deployer.address}`);
  console.log(`   npx hardhat verify --network ${hre.network.name} ${presaleAddress} ${tokenAddress} ${deployer.address}`);
  console.log(`   npx hardhat verify --network ${hre.network.name} ${stakingAddress} ${tokenAddress} ${deployer.address}`);
  console.log("\n2. Start presale:");
  console.log(`   await presale.startPresale()`);
  console.log("\n3. Enable trading:");
  console.log(`   await token.enableTrading()`);

  console.log("\n🎉 Deployment Complete!");
  console.log("=".repeat(60));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
