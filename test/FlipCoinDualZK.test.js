const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FlipCoinDualZK", function () {
  let flipCoin;
  let verifier;
  let owner;
  let player;
  let house;

  // Configuración de test
  const VRF_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625"; // Sepolia
  const KEY_HASH = "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c";
  const SUBSCRIPTION_ID = 0; // Usar 0 para activar el mock en Hardhat
  const HOUSE_FEE = 100; // 1%
  const MIN_BET = ethers.utils.parseEther("0.001");
  const MAX_BET = ethers.utils.parseEther("1.0");

  beforeEach(async function () {
    [owner, player, house] = await ethers.getSigners();

    // Desplegar verificador (mock para tests de integración)
    const MockVerifier = await ethers.getContractFactory("MockVerifier");
    verifier = await MockVerifier.deploy();
    await verifier.deployed();

    // Desplegar contrato principal
    const FlipCoinDualZK = await ethers.getContractFactory("FlipCoinDualZK");
    flipCoin = await FlipCoinDualZK.deploy(
      VRF_COORDINATOR,
      KEY_HASH,
      SUBSCRIPTION_ID,
      HOUSE_FEE,
      MIN_BET,
      MAX_BET,
      verifier.address
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
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-commit"));

      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount })
      )
        .to.emit(flipCoin, "BetCreated")
        .withArgs(0, player.address, house.address, betAmount);

      const betInfo = await flipCoin.getBetInfo(0);
      expect(betInfo.player).to.equal(player.address);
      expect(betInfo.house).to.equal(house.address);
      expect(betInfo.amount).to.equal(betAmount);
      expect(betInfo.playerCommit).to.equal(playerCommit);
    });

    it("Should reject zero amount bet", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-commit"));

      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: 0 })
      ).to.be.revertedWith("Bet below minimum");
    });

    it("Should reject bet below minimum", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-commit"));
      const smallBet = ethers.utils.parseEther("0.0001");

      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: smallBet })
      ).to.be.revertedWith("Bet below minimum");
    });

    it("Should reject bet above maximum", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-commit"));
      const largeBet = ethers.utils.parseEther("2.0");

      await expect(
        flipCoin.connect(player).createBet(house.address, playerCommit, { value: largeBet })
      ).to.be.revertedWith("Bet above maximum");
    });

    it("Should reject invalid house address", async function () {
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-commit"));
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
    let houseCommit;

    beforeEach(async function () {
      const betAmount = ethers.utils.parseEther("0.01");
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("player-commit"));
      houseCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("house-commit"));

      await flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount });
      betId = 0;
    });

    it("Should allow house to commit", async function () {
      await expect(
        flipCoin.connect(house).houseCommit(betId, houseCommit)
      )
        .to.emit(flipCoin, "HouseCommitted")
        .withArgs(betId, house.address, houseCommit);

      const betInfo = await flipCoin.getBetInfo(betId);
      expect(betInfo.houseCommitHash).to.equal(houseCommit);
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

  describe("Dual ZK Settlement", function () {
    let betId;
    let playerPreimage;
    let housePreimage;
    let playerCommit;
    let houseCommit;

    beforeEach(async function () {
      const betAmount = ethers.utils.parseEther("0.01");
      
      // Crear preimágenes de 512 bits (16 uint32)
      playerPreimage = Array(16).fill(0).map((_, i) => i + 1); // [1, 2, 3, ..., 16]
      housePreimage = Array(16).fill(0).map((_, i) => i + 100); // [100, 101, 102, ..., 115]
      
      playerCommit = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint32[16]"], [playerPreimage]));
      houseCommit = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint32[16]"], [housePreimage]));

      await flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount });
      await flipCoin.connect(house).houseCommit(0, houseCommit);
      betId = 0;
    });

    it("Should settle bet with dual ZK proof (house settles)", async function () {
      // Forzar índice VRF determinista
      await flipCoin.connect(owner).setRandomIndexForTest(betId, 137);

      // Señales públicas simuladas: [playerCommit, houseCommit, bitIndex, expectedResult]
      const pub = [
        playerCommit,
        houseCommit,
        ethers.BigNumber.from(137),
        ethers.BigNumber.from(1),
        ethers.BigNumber.from(0)
      ];
      const a = [0,0];
      const b = [[0,0],[0,0]];
      const c = [0,0];

      // La casa liquida la apuesta (tiene acceso a ambas preimágenes)
      await expect(
        flipCoin.connect(house).settleBetWithDualZK(
          betId,
          a,
          b,
          c,
          pub
        )
      ).to.emit(flipCoin, "BetSettled");

      const betInfo = await flipCoin.getBetInfo(betId);
      expect(betInfo.settled).to.be.true;
    });

    it("Should reject settlement before VRF", async function () {
      const a = [0,0];
      const b = [[0,0],[0,0]];
      const c = [0,0];
      const pub = [
        ethers.constants.HashZero,
        ethers.constants.HashZero,
        ethers.BigNumber.from(0),
        ethers.BigNumber.from(1),
        ethers.BigNumber.from(0)
      ];

      // Crear nueva apuesta sin VRF
      const betAmount = ethers.utils.parseEther("0.01");
      const newPlayerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("new-commit"));
      
      await flipCoin.connect(player).createBet(house.address, newPlayerCommit, { value: betAmount });
      const newBetId = 1;

      await expect(
        flipCoin.connect(player).settleBetWithDualZK(newBetId, a, b, c, pub)
      ).to.be.revertedWith("VRF not fulfilled yet");
    });

    it("Should reject invalid expected result", async function () {
      const a = [0,0];
      const b = [[0,0],[0,0]];
      const c = [0,0];
      const invalidResult = 2; // Debe ser 0 o 1

      await expect(
        flipCoin.connect(player).settleBetWithDualZK(
          betId,
          a,
          b,
          c,
          [playerCommit, houseCommit, ethers.BigNumber.from(137), ethers.BigNumber.from(invalidResult), ethers.BigNumber.from(0)]
        )
      ).to.be.revertedWith("Invalid expected result");
    });
  });

  describe("Administration", function () {
    it("Should allow owner to update house fee", async function () {
      const newFee = 200; // 2%
      await flipCoin.connect(owner).updateHouseFee(newFee);
      expect(await flipCoin.houseFee()).to.equal(newFee);
    });

    it("Should reject house fee too high", async function () {
      const highFee = 2000; // 20%
      await expect(
        flipCoin.connect(owner).updateHouseFee(highFee)
      ).to.be.revertedWith("Fee too high");
    });

    it("Should allow owner to update bet limits", async function () {
      const newMinBet = ethers.utils.parseEther("0.002");
      const newMaxBet = ethers.utils.parseEther("2.0");
      
      await flipCoin.connect(owner).updateBetLimits(newMinBet, newMaxBet);
      expect(await flipCoin.minBetAmount()).to.equal(newMinBet);
      expect(await flipCoin.maxBetAmount()).to.equal(newMaxBet);
    });

    it("Should reject invalid bet limits", async function () {
      const invalidMinBet = ethers.utils.parseEther("0.002");
      const invalidMaxBet = ethers.utils.parseEther("0.001"); // Menor que min
      
      await expect(
        flipCoin.connect(owner).updateBetLimits(invalidMinBet, invalidMaxBet)
      ).to.be.revertedWith("Invalid max bet");
    });

    it("Should reject non-owner from admin functions", async function () {
      await expect(
        flipCoin.connect(player).updateHouseFee(200)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow owner to emergency withdraw", async function () {
      // Crear una apuesta para tener fondos
      const betAmount = ethers.utils.parseEther("0.01");
      const playerCommit = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-commit"));
      
      await flipCoin.connect(player).createBet(house.address, playerCommit, { value: betAmount });
      
      const initialBalance = await ethers.provider.getBalance(owner.address);
      await flipCoin.connect(owner).emergencyWithdraw();
      const finalBalance = await ethers.provider.getBalance(owner.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should reject emergency withdraw from non-owner", async function () {
      await expect(
        flipCoin.connect(player).emergencyWithdraw()
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
});
