const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FlipCoinSimple", function () {
  let flipCoin;
  let owner;
  let player1;

  beforeEach(async function () {
    [owner, player1] = await ethers.getSigners();
    
    const FlipCoinSimple = await ethers.getContractFactory("FlipCoinSimple");
    flipCoin = await FlipCoinSimple.deploy();
  });

  it("Should set the right owner", async function () {
    expect(await flipCoin.owner()).to.equal(owner.address);
  });

  it("Should set the right house fee", async function () {
    expect(await flipCoin.houseFeeBP()).to.equal(200);
  });

  it("Should start with nextBetId = 0", async function () {
    expect(await flipCoin.nextBetId()).to.equal(0);
  });

  it("Should reject zero amount bet", async function () {
    const nonce = 12345;
    
    await expect(flipCoin.connect(player1).placeBet(nonce, { value: 0 }))
      .to.be.revertedWith("stake>0");
  });

  it("Should reject withdrawal from non-owner", async function () {
    await expect(flipCoin.connect(player1).withdraw())
      .to.be.revertedWith("only owner");
  });
});
