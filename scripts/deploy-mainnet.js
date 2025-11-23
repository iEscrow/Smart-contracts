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
  const PRESALE_RATE = "66666666666666666667"; // ~66.67 tokens per USD = $0.015 per token (18 decimals)
  const MAX_TOKENS_FOR_PRESALE = hre.ethers.parseEther("5000000000"); // 5B tokens
  const PRESALE_LAUNCH_DATE = 1764068400; // Nov 25, 2025 11:00 AM UTC

  // Step 1: Deploy ESCROW Token
  console.log("\n=== Step 1: Deploying ESCROW Token ===");
  const EscrowToken = await hre.ethers.getContractFactory("EscrowToken");
  const escrowToken = await EscrowToken.deploy();
  await escrowToken.waitForDeployment();
  const escrowTokenAddress = await escrowToken.getAddress();
  console.log("ESCROW Token deployed at:", escrowTokenAddress);
  
  // Verify ESCROW Token
  console.log("Verifying ESCROW Token...");
  const totalSupply = await escrowToken.totalSupply();
  if (totalSupply !== hre.ethers.parseEther("8400000000")) {
    throw new Error("Total supply mismatch");
  }
  console.log("[OK] ESCROW Token verified");

  // Step 2: Deploy Authorizer
  console.log("\n=== Step 2: Deploying Authorizer ===");
  const Authorizer = await hre.ethers.getContractFactory("Authorizer");
  const authorizer = await Authorizer.deploy(BACKEND_SIGNER, OWNER_ADDRESS);
  await authorizer.waitForDeployment();
  const authorizerAddress = await authorizer.getAddress();
  console.log("Authorizer deployed at:", authorizerAddress);
  
  // Verify Authorizer
  console.log("Verifying Authorizer...");
  const signer = await authorizer.signer();
  const owner = await authorizer.owner();
  if (signer !== BACKEND_SIGNER) throw new Error("Signer mismatch");
  if (owner !== OWNER_ADDRESS) throw new Error("Owner mismatch");
  console.log("[OK] Authorizer verified");

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
  
  // Verify DevTreasury
  console.log("Verifying DevTreasury...");
  const linkedPresale = await devTreasury.presale();
  if (linkedPresale !== predictedPresaleAddress) {
    throw new Error("Presale address mismatch in DevTreasury");
  }
  console.log("[OK] DevTreasury verified");

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
  
  // Verify Presale
  console.log("Verifying Presale Contract...");
  const presaleToken = await presale.presaleToken();
  const presaleRateCheck = await presale.presaleRate();
  const maxTokens = await presale.maxTokensToMint();
  const devTreasuryCheck = await presale.devTreasury();
  const presaleOwner = await presale.owner();
  const treasury = await presale.treasury();
  const escrowStartTime = await presale.escrowPresaleStartTime();
  const escrowRound = await presale.escrowCurrentRound();
  const escrowEnded = await presale.escrowPresaleEnded();
  const gasBuffer = await presale.gasBuffer();
  
  if (presaleToken !== escrowTokenAddress) throw new Error("Presale token mismatch");
  if (presaleRateCheck.toString() !== PRESALE_RATE) throw new Error("Presale rate mismatch");
  if (maxTokens !== MAX_TOKENS_FOR_PRESALE) throw new Error("Max tokens mismatch");
  if (devTreasuryCheck !== devTreasuryAddress) throw new Error("Dev treasury mismatch");
  if (presaleOwner !== OWNER_ADDRESS) throw new Error("Owner mismatch");
  if (treasury !== OWNER_ADDRESS) throw new Error("Treasury mismatch");
  if (escrowStartTime !== BigInt(PRESALE_LAUNCH_DATE)) throw new Error("Launch date mismatch");
  if (escrowRound !== 1n) throw new Error("Should be in round 1");
  if (escrowEnded !== false) throw new Error("Should not be ended");
  if (gasBuffer !== hre.ethers.parseEther("0.0005")) throw new Error("Gas buffer mismatch");
  console.log("[OK] Presale Contract verified");

  // Step 6: Mint presale allocation
  console.log("\n=== Step 6: Minting Presale Allocation ===");
  const mintTx = await escrowToken.mintPresaleAllocation(presaleAddress);
  await mintTx.wait();
  console.log("Presale allocation minted successfully");
  
  // Verify Presale Balance
  console.log("Verifying Presale Token Balance...");
  const presaleBalance = await escrowToken.balanceOf(presaleAddress);
  if (presaleBalance !== MAX_TOKENS_FOR_PRESALE) {
    throw new Error("Presale balance mismatch");
  }
  console.log("[OK] Presale has correct token balance:", hre.ethers.formatEther(presaleBalance), "ESCROW");

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
