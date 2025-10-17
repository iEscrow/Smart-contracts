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

  // Fund the treasury (beneficiaries are already initialized in contract)
  await (await treasury.fundTreasury()).wait();
  console.log("Treasury funded successfully");

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