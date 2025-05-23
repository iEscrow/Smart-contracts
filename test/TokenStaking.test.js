const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UnityStakeV5 (TokenStaking)", function() {
  let staking, token, owner, user;
  const ONE = ethers.utils.parseEther("1");

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    // Desplegamos el mock ERC20Mintable
    const ERC20Mintable = await ethers.getContractFactory("ERC20Mintable");
    token = await ERC20Mintable.deploy();
    await token.deployed();

    // Mint inicial para user
    await token.connect(owner).mint(user.address, ethers.utils.parseEther("100"));

    // Desplegamos el contrato de Staking
    const Staking = await ethers.getContractFactory("UnityStakeV5");
    staking = await Staking.deploy(
      token.address,
      2000,   // apyRate
      1,      // minimumStakingAmount
      1000,   // maxStakeTokenLimit
      500     // earlyUnstakeFeePercentage (5%)
    );
    await staking.deployed();
  });

  it("should allow staking and list active stakes", async () => {
    // stake de 10 tokens por 3 días
    await token.connect(user).approve(staking.address, ONE.mul(10));
    await staking.connect(user).stake(10, 3);

    const stakes = await staking.getActiveStakes(user.address);
    expect(stakes.length).to.equal(1);
    expect(stakes[0].amount).to.equal(10);
  });

  it("supports multiple stakes and lists them all", async () => {
    await token.connect(user).approve(staking.address, ONE.mul(15));
    await staking.connect(user).stake(10, 2);
    await staking.connect(user).stake(5, 1);

    const stakes = await staking.getActiveStakes(user.address);
    expect(stakes.length).to.equal(2);
    const amounts = stakes.map(s => s.amount.toNumber());
    expect(amounts).to.include.members([10, 5]);
  });

  it("burns tokens on stake", async () => {
    const beforeBal = await token.balanceOf(user.address);
    await token.connect(user).approve(staking.address, ONE.mul(10));
    await staking.connect(user).stake(10, 1);
    const afterBal = await token.balanceOf(user.address);

    expect(afterBal).to.equal(beforeBal.sub(ONE.mul(10)));
  });

  it("should apply early unstake fee", async () => {
    await token.connect(user).approve(staking.address, ONE.mul(10));
    await staking.connect(user).stake(10, 3);

    // unstake inmediato → fee
    const tx = await staking.connect(user).unstakeSpecific(0);
    const receipt = await tx.wait();
    const feeEvent = receipt.events.find(e => e.event === "EarlyUnStakeFee");
    expect(feeEvent).to.exist;
  });

  it("should return full reward after maturity (no fee)", async () => {
    // Proveer supply para recompensas/mint
    await token.connect(owner).mint(staking.address, ONE.mul(20));

    await token.connect(user).approve(staking.address, ONE.mul(10));
    await staking.connect(user).stake(10, 1);

    // Avanzar 1 día
    await ethers.provider.send("evm_increaseTime", [24 * 3600]);
    await ethers.provider.send("evm_mine");

    const tx = await staking.connect(user).unstakeSpecific(0);
    const receipt = await tx.wait();
    const feeEvent = receipt.events.find(e => e.event === "EarlyUnStakeFee");
    expect(feeEvent).to.be.undefined;
  });

  it("remints principal on unstake after maturity", async () => {
    // Proveer supply para mint
    await token.connect(owner).mint(staking.address, ONE.mul(20));

    await token.connect(user).approve(staking.address, ONE.mul(10));
    await staking.connect(user).stake(10, 1);

    // Avanzar 1 día
    await ethers.provider.send("evm_increaseTime", [24 * 3600]);
    await ethers.provider.send("evm_mine");

    const beforeBal = await token.balanceOf(user.address);
    await staking.connect(user).unstakeSpecific(0);
    const afterBal = await token.balanceOf(user.address);

    // Recupera ~10 tokens (principal) más la recompensa neta
    expect(afterBal.sub(beforeBal)).to.be.closeTo(ONE.mul(10), ONE);
  });

  it("only unstakes the selected stake among many", async () => {
    await token.connect(user).approve(staking.address, ONE.mul(30));
    await staking.connect(user).stake(10, 1);
    await staking.connect(user).stake(5, 1);
    await staking.connect(user).stake(15, 1);

    // Unstake solo el índice 1 (amount 5)
    await staking.connect(user).unstakeSpecific(1);

    const remaining = await staking.getActiveStakes(user.address);
    expect(remaining.length).to.equal(2);
    const amounts = remaining.map(s => s.amount.toNumber());
    expect(amounts).to.not.include(5);
  });
});
