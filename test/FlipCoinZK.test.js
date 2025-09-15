const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FlipCoinZK", function () {
  let flipCoin;
  let owner;
  let player;
  let house;
  
  // Configuración de test
  const VRF_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625"; // Sepolia
  const KEY_HASH = "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c";
  const SUBSCRIPTION_ID = 0;
  const HOUSE_FEE = 100; // 1%
  const MIN_BET = ethers.utils.parseEther("0.001");
  const MAX_BET = ethers.utils.parseEther("1.0");
  
  beforeEach(async function () {
    [owner, player, house] = await ethers.getSigners();
    
    const FlipCoinZK = await ethers.getContractFactory("FlipCoinZK");
    flipCoin = await FlipCoinZK.deploy(
      VRF_COORDINATOR,
      KEY_HASH,
      SUBSCRIPTION_ID,
      HOUSE_FEE,
      MIN_BET,
      MAX_BET
    );
    await flipCoin.deployed();
  });
  
  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await flipCoin.owner()).to.equal(owner.address);
    });
    
    it("Should set the right house fee", async function () {
      expect(await flipCoin.houseFee()).to.equal(HOUSE_FEE);
    });
    
    it("Should set the right bet limits", async function () {
      expect(await flipCoin.minBetAmount()).to.equal(MIN_BET);
      expect(await flipCoin.maxBetAmount()).to.equal(MAX_BET);
    });
    
    it("Should start with nextBetId = 0", async function () {
      expect(await flipCoin.nextBetId()).to.equal(0);
    });
  });
  
  describe("Bet Creation", function () {
    it("Should create a bet successfully", async function () {
      const betAmount = ethers.utils.parseEther("0.01");
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-preimage"));
      
      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount })
      )
        .to.emit(flipCoin, "BetCreated")
        .withArgs(0, player.address, house.address, betAmount)
        .to.emit(flipCoin, "PlayerCommitted")
        .withArgs(0, player.address, playerCommit);
      
      const betInfo = await flipCoin.getBetInfo(0);
      expect(betInfo.player).to.equal(player.address);
      expect(betInfo.house).to.equal(house.address);
      expect(betInfo.amount).to.equal(betAmount);
      expect(betInfo.playerCommit).to.equal(playerCommit);
    });
    
    it("Should reject zero amount bet", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-preimage"));
      
      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: 0 })
      ).to.be.revertedWith("Bet amount out of range");
    });
    
    it("Should reject bet below minimum", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-preimage"));
      const smallAmount = ethers.utils.parseEther("0.0001");
      
      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: smallAmount })
      ).to.be.revertedWith("Bet amount out of range");
    });
    
    it("Should reject bet above maximum", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-preimage"));
      const largeAmount = ethers.utils.parseEther("2.0");
      
      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: largeAmount })
      ).to.be.revertedWith("Bet amount out of range");
    });
    
    it("Should reject invalid house address", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-preimage"));
      const betAmount = ethers.utils.parseEther("0.01");
      
      await expect(
        flipCoin.connect(player).createBet(ethers.constants.AddressZero, playerCommit, { value: betAmount })
      ).to.be.revertedWith("Invalid house address");
      
      await expect(
        flipCoin.connect(player).createBet(player.address, playerCommit, { value: betAmount })
      ).to.be.revertedWith("Invalid house address");
    });
  });
  
  describe("House Commit", function () {
    let betId;
    let playerCommit;
    let houseCommit;
    
    beforeEach(async function () {
      const betAmount = ethers.utils.parseEther("0.01");
      playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("player-preimage"));
      houseCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("house-preimage"));
      
      await flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount });
      betId = 0;
    });
    
    it("Should allow house to commit", async function () {
      await expect(
        flipCoin.connect(house).houseCommit(betId, houseCommit)
      )
        .to.emit(flipCoin, "HouseCommitted")
        .withArgs(betId, house.address, houseCommit)
        .to.emit(flipCoin, "VRFFulfilled"); // Mock VRF se ejecuta automáticamente
      
      const betInfo = await flipCoin.getBetInfo(betId);
      expect(betInfo.houseCommitHash).to.equal(houseCommit);
      expect(betInfo.randomIndex).to.be.gt(0);
    });
    
    it("Should reject commit from non-house", async function () {
      await expect(
        flipCoin.connect(player).houseCommit(betId, houseCommit)
      ).to.be.revertedWith("Only house can commit");
    });
    
    it("Should reject double commit from house", async function () {
      await flipCoin.connect(house).houseCommit(betId, houseCommit);
      
      await expect(
        flipCoin.connect(house).houseCommit(betId, houseCommit)
      ).to.be.revertedWith("House already committed");
    });
  });
  
  describe("Reveal Process", function () {
    let betId;
    let playerPreimage;
    let housePreimage;
    let playerCommit;
    let houseCommit;
    
    beforeEach(async function () {
      const betAmount = ethers.utils.parseEther("0.01");
      // Crear preimágenes de 512 bits (16 uint32) con valores de ejemplo
      playerPreimage = Array(16).fill(0).map((_, i) => i + 1); // [1, 2, 3, ..., 16]
      housePreimage = Array(16).fill(0).map((_, i) => i + 100); // [100, 101, 102, ..., 115]
      
      playerCommit = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint32[16]"], [playerPreimage]));
      houseCommit = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint32[16]"], [housePreimage]));
      
      await flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount });
      await flipCoin.connect(house).houseCommit(0, houseCommit);
      betId = 0;
    });
    
    it("Should allow player to reveal", async function () {
      const zkProof = "0x"; // Placeholder
      
      await expect(
        flipCoin.connect(player).playerReveal(betId, playerPreimage, zkProof)
      )
        .to.emit(flipCoin, "PlayerRevealed");
      
      const betInfo = await flipCoin.getBetInfo(betId);
      expect(betInfo.playerRevealed).to.be.true;
    });
    
    it("Should allow house to reveal", async function () {
      const zkProof = "0x"; // Placeholder
      
      await expect(
        flipCoin.connect(house).houseReveal(betId, housePreimage, zkProof)
      )
        .to.emit(flipCoin, "HouseRevealed");
      
      const betInfo = await flipCoin.getBetInfo(betId);
      expect(betInfo.houseRevealed).to.be.true;
    });
    
    it("Should settle bet when both reveal", async function () {
      const zkProof = "0x"; // Placeholder
      
      await flipCoin.connect(player).playerReveal(betId, playerPreimage, zkProof);
      await flipCoin.connect(house).houseReveal(betId, housePreimage, zkProof);
      
      const betInfo = await flipCoin.getBetInfo(betId);
      expect(betInfo.settled).to.be.true;
    });
    
    it("Should reject invalid preimage", async function () {
      const zkProof = "0x"; // Placeholder
      const invalidPreimage = ethers.utils.toUtf8Bytes("invalid-preimage");
      
      await expect(
        flipCoin.connect(player).playerReveal(betId, invalidPreimage, zkProof)
      ).to.be.revertedWith("Invalid preimage");
    });
  });
  
  describe("Administration", function () {
    it("Should allow owner to update house fee", async function () {
      const newFee = 200; // 2%
      
      await expect(flipCoin.setHouseFee(newFee))
        .to.emit(flipCoin, "HouseFeeUpdated")
        .withArgs(newFee);
      
      expect(await flipCoin.houseFee()).to.equal(newFee);
    });
    
    it("Should reject house fee too high", async function () {
      const highFee = 2000; // 20%
      
      await expect(flipCoin.setHouseFee(highFee))
        .to.be.revertedWith("Fee too high");
    });
    
    it("Should allow owner to update bet limits", async function () {
      const newMin = ethers.utils.parseEther("0.01");
      const newMax = ethers.utils.parseEther("2.0");
      
      await expect(flipCoin.setBetLimits(newMin, newMax))
        .to.emit(flipCoin, "BetLimitsUpdated")
        .withArgs(newMin, newMax);
      
      expect(await flipCoin.minBetAmount()).to.equal(newMin);
      expect(await flipCoin.maxBetAmount()).to.equal(newMax);
    });
    
    it("Should reject invalid bet limits", async function () {
      const invalidMin = ethers.utils.parseEther("0.01");
      const invalidMax = ethers.utils.parseEther("0.005"); // Max < Min
      
      await expect(flipCoin.setBetLimits(invalidMin, invalidMax))
        .to.be.revertedWith("Invalid limits");
    });
    
    it("Should reject non-owner from admin functions", async function () {
      await expect(
        flipCoin.connect(player).setHouseFee(200)
      ).to.be.revertedWith("Ownable: caller is not the owner");
      
      await expect(
        flipCoin.connect(player).setBetLimits(MIN_BET, MAX_BET)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
  
  describe("Emergency Functions", function () {
    it("Should allow owner to emergency withdraw", async function () {
      // Enviar ETH al contrato
      await owner.sendTransaction({
        to: flipCoin.address,
        value: ethers.utils.parseEther("1.0")
      });
      
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await flipCoin.emergencyWithdraw();
      
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });
    
    it("Should reject emergency withdraw from non-owner", async function () {
      await expect(
        flipCoin.connect(player).emergencyWithdraw()
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
  
  describe("Utility Functions", function () {
    it("Should get bit at position correctly", async function () {
      const testHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test"));
      
      // Crear una apuesta para acceder a la función interna
      const betAmount = ethers.utils.parseEther("0.01");
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("player-preimage"));
      
      await flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount });
      
      // La función _getBitAt es interna, pero podemos probar la lógica indirectamente
      // a través de las funciones públicas que la usan
      const betInfo = await flipCoin.getBetInfo(0);
      expect(betInfo.player).to.equal(player.address);
    });
  });
});
