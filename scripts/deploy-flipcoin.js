const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Desplegando FlipCoinZK...");
  
  // Configuración para testnet (ejemplo con Sepolia)
  const VRF_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625"; // Sepolia VRF Coordinator
  const KEY_HASH = "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c"; // Sepolia key hash
  const SUBSCRIPTION_ID = 0; // Necesita ser configurado en Chainlink VRF
  
  // Parámetros del contrato
  const HOUSE_FEE = 100; // 1% en basis points
  const MIN_BET_AMOUNT = ethers.utils.parseEther("0.001"); // 0.001 ETH
  const MAX_BET_AMOUNT = ethers.utils.parseEther("1.0"); // 1 ETH
  
  // Desplegar contrato
  const FlipCoinZK = await ethers.getContractFactory("FlipCoinZK");
  const flipCoin = await FlipCoinZK.deploy(
    VRF_COORDINATOR,
    KEY_HASH,
    SUBSCRIPTION_ID,
    HOUSE_FEE,
    MIN_BET_AMOUNT,
    MAX_BET_AMOUNT
  );
  
  await flipCoin.deployed();
  
  console.log("✅ FlipCoinZK desplegado en:", flipCoin.address);
  console.log("📊 Configuración:");
  console.log("  - VRF Coordinator:", VRF_COORDINATOR);
  console.log("  - Key Hash:", KEY_HASH);
  console.log("  - Subscription ID:", SUBSCRIPTION_ID);
  console.log("  - House Fee:", HOUSE_FEE, "basis points");
  console.log("  - Min Bet:", ethers.utils.formatEther(MIN_BET_AMOUNT), "ETH");
  console.log("  - Max Bet:", ethers.utils.formatEther(MAX_BET_AMOUNT), "ETH");
  
  // Verificar en Etherscan (opcional)
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("⏳ Esperando confirmaciones...");
    await flipCoin.deployTransaction.wait(6);
    
    try {
      await hre.run("verify:verify", {
        address: flipCoin.address,
        constructorArguments: [
          VRF_COORDINATOR,
          KEY_HASH,
          SUBSCRIPTION_ID,
          HOUSE_FEE,
          MIN_BET_AMOUNT,
          MAX_BET_AMOUNT
        ],
      });
      console.log("✅ Contrato verificado en Etherscan");
    } catch (error) {
      console.log("❌ Error verificando contrato:", error.message);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error desplegando:", error);
    process.exit(1);
  });
