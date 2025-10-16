const { ethers } = require("hardhat");

async function main() {
  // Deploy MockEscrowTokenNoMint
  const MockToken = await ethers.getContractFactory("MockEscrowTokenNoMint");
  const token = await MockToken.deploy();
  await token.waitForDeployment();
  console.log(`MockToken deployed to: ${await token.getAddress()}`);

  // Deploy EscrowTeamTreasury
  const Treasury = await ethers.getContractFactory("EscrowTeamTreasury");
  const treasury = await Treasury.deploy(await token.getAddress());
  await treasury.waitForDeployment();
  console.log(`Treasury deployed to: ${await treasury.getAddress()}`);

  // Mint some initial tokens to the owner
  const [owner] = await ethers.getSigners();
  const amount = await treasury.TOTAL_ALLOCATION();
  await (await token.mint(owner.address, amount)).wait();
  console.log(`Minted ${amount.toString()} tokens to owner`);

  // Approve treasury to spend tokens
  await (await token.approve(await treasury.getAddress(), amount)).wait();
  console.log("Approved treasury to spend tokens");

  // Fund the treasury
  await (await treasury.fundTreasury()).wait();
  console.log("Treasury funded successfully");

  // Add team beneficiaries (10M tokens each = 50M total for team, 950M for treasury/other allocations)
  const teamBeneficiaries = [
    "0x04435410a78192baAfa00c72C659aD3187a2C2cF",
    "0x9005132849bC9585A948269D96F23f56e5981A61",
    "0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74",
    "0x03a54ADc7101393776C200529A454b4cDc3545C5",
    "0x04D83B2BdF89fe4C781Ec8aE3D672c610080B319"
  ];

  const teamAllocationAmount = ethers.parseUnits("10000000", 18); // 10M tokens each

  for (let i = 0; i < teamBeneficiaries.length; i++) {
    await (await treasury.addBeneficiary(teamBeneficiaries[i], teamAllocationAmount)).wait();
    console.log(`Added team beneficiary ${i + 1}: ${teamBeneficiaries[i]} with ${ethers.formatEther(teamAllocationAmount)} tokens`);
  }

  // Lock allocations
  await (await treasury.lockAllocations()).wait();
  console.log("Allocations locked");

  console.log("\nDeployment and setup completed successfully!");
  console.log(`Token address: ${await token.getAddress()}`);
  console.log(`Treasury address: ${await treasury.getAddress()}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });