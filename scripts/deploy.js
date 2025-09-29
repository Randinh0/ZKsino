const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Desplegando contratos en Hardhat local...");

  const [deployer] = await ethers.getSigners();
  console.log("Desplegando con la cuenta:", deployer.address);
  console.log("Balance de la cuenta:", (await deployer.getBalance()).toString());

  // Desplegar MockVerifier para desarrollo
  const MockVerifier = await ethers.getContractFactory("MockVerifier");
  const mockVerifier = await MockVerifier.deploy();
  await mockVerifier.deployed();
  console.log("✅ MockVerifier desplegado en:", mockVerifier.address);

  // Desplegar FlipCoinDualZK
  const VRF_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625"; // Mock
  const KEY_HASH = "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c";
  const SUBSCRIPTION_ID = 0; // Mock mode
  const HOUSE_FEE = 100; // 1%
  const MIN_BET = ethers.utils.parseEther("0.001");
  const MAX_BET = ethers.utils.parseEther("1.0");

  const FlipCoinDualZK = await ethers.getContractFactory("FlipCoinDualZK");
  const flipCoin = await FlipCoinDualZK.deploy(
    VRF_COORDINATOR,
    KEY_HASH,
    SUBSCRIPTION_ID,
    HOUSE_FEE,
    MIN_BET,
    MAX_BET,
    mockVerifier.address
  );
  await flipCoin.deployed();
  console.log("✅ FlipCoinDualZK desplegado en:", flipCoin.address);

  // Guardar direcciones para el frontend
  const addresses = {
    MockVerifier: mockVerifier.address,
    FlipCoinDualZK: flipCoin.address,
    network: "localhost",
    chainId: 31337
  };

  const fs = require('fs');
  fs.writeFileSync('./contract-addresses.json', JSON.stringify(addresses, null, 2));
  console.log("📄 Direcciones guardadas en contract-addresses.json");

  console.log("\n🎉 ¡Despliegue completado!");
  console.log("📋 Direcciones de contratos:");
  console.log("   MockVerifier:", mockVerifier.address);
  console.log("   FlipCoinDualZK:", flipCoin.address);
  console.log("\n🔗 Conecta tu frontend a: http://localhost:8545");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
