const hre = require("hardhat");

async function main() {
  console.log("========================================");
  console.log("MAINNET DEPLOYMENT - NO TEST TOKENS");
  console.log("========================================");

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name);
  console.log("Chain ID:", hre.network.config.chainId);

  // Configuration
  const OWNER_ADDRESS = "0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2";
  const BACKEND_SIGNER = "0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2";
  const PRESALE_RATE = "666666666666666666667"; // ~666.67 tokens per USD (18 decimals)
  const MAX_TOKENS_FOR_PRESALE = hre.ethers.parseEther("5000000000"); // 5B tokens

  // Step 1: Deploy ESCROW Token
  console.log("\n=== Step 1: Deploying ESCROW Token ===");
  const EscrowToken = await hre.ethers.getContractFactory("EscrowToken");
  const escrowToken = await EscrowToken.deploy();
  await escrowToken.waitForDeployment();
  const escrowTokenAddress = await escrowToken.getAddress();
  console.log("ESCROW Token deployed at:", escrowTokenAddress);

  // Step 2: Deploy Authorizer
  console.log("\n=== Step 2: Deploying Authorizer ===");
  const Authorizer = await hre.ethers.getContractFactory("Authorizer");
  const authorizer = await Authorizer.deploy(BACKEND_SIGNER, OWNER_ADDRESS);
  await authorizer.waitForDeployment();
  const authorizerAddress = await authorizer.getAddress();
  console.log("Authorizer deployed at:", authorizerAddress);

  // Step 3: Calculate future presale address
  console.log("\n=== Step 3: Calculating Future Presale Address ===");
  const currentNonce = await hre.ethers.provider.getTransactionCount(deployer.address);
  const predictedPresaleAddress = hre.ethers.getCreateAddress({
    from: deployer.address,
    nonce: currentNonce + 1
  });
  console.log("Predicted Presale Address:", predictedPresaleAddress);

  // Step 4: Deploy DevTreasury
  console.log("\n=== Step 4: Deploying DevTreasury ===");
  const DevTreasury = await hre.ethers.getContractFactory("DevTreasury");
  const devTreasury = await DevTreasury.deploy(predictedPresaleAddress);
  await devTreasury.waitForDeployment();
  const devTreasuryAddress = await devTreasury.getAddress();
  console.log("DevTreasury deployed at:", devTreasuryAddress);
  console.log("DevTreasury linked to future presale:", predictedPresaleAddress);

  // Step 5: Deploy MultiTokenPresale
  console.log("\n=== Step 5: Deploying Presale Contract ===");
  const MultiTokenPresale = await hre.ethers.getContractFactory("MultiTokenPresale");
  const presale = await MultiTokenPresale.deploy(
    escrowTokenAddress,
    PRESALE_RATE,
    MAX_TOKENS_FOR_PRESALE,
    devTreasuryAddress
  );
  await presale.waitForDeployment();
  const presaleAddress = await presale.getAddress();
  console.log("Presale Contract deployed at:", presaleAddress);

  // Verify prediction
  if (presaleAddress !== predictedPresaleAddress) {
    throw new Error("Presale address mismatch!");
  }
  console.log("SUCCESS: Presale address matches prediction");

  // Step 6: Mint presale allocation
  console.log("\n=== Step 6: Minting Presale Allocation ===");
  const mintTx = await escrowToken.mintPresaleAllocation(presaleAddress);
  await mintTx.wait();
  console.log("Presale allocation minted successfully");

  // Display summary
  console.log("\n========== DEPLOYMENT SUMMARY ==========");
  console.log("Network: ETHEREUM MAINNET");
  console.log("Chain ID:", hre.network.config.chainId);
  console.log("\n=== Core Contracts ===");
  console.log("ESCROW Token:", escrowTokenAddress);
  console.log("Authorizer:", authorizerAddress);
  console.log("DevTreasury:", devTreasuryAddress);
  console.log("Presale Contract:", presaleAddress);
  
  console.log("\n=== Configuration Steps (Owner Only) ===");
  console.log("NOTE: The following must be done by owner:", OWNER_ADDRESS);
  console.log("1. presale.setGasBuffer(240000000000000)"); // 0.00024 ETH (~$1)
  console.log("2. presale.updateAuthorizer(" + authorizerAddress + ")");
  console.log("3. presale.setVoucherSystemEnabled(true)");

  console.log("\n========== NEXT STEPS ==========");
  console.log("1. Verify contracts on Etherscan:");
  console.log("   npx hardhat verify --network mainnet", escrowTokenAddress);
  console.log("   npx hardhat verify --network mainnet", authorizerAddress, BACKEND_SIGNER, OWNER_ADDRESS);
  console.log("   npx hardhat verify --network mainnet", devTreasuryAddress, presaleAddress);
  console.log("   npx hardhat verify --network mainnet", presaleAddress, escrowTokenAddress, PRESALE_RATE, MAX_TOKENS_FOR_PRESALE.toString(), devTreasuryAddress);
  console.log("2. Owner configures presale (see configuration steps above)");
  console.log("3. Start presale: presale.autoStartIEscrowPresale()");

  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETED!");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
