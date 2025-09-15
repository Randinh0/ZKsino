const hre = require("hardhat");

async function main() {
  console.log("Desplegando FlipCoinSimple...");
  
  const FlipCoinSimple = await hre.ethers.getContractFactory("FlipCoinSimple");
  const flipCoin = await FlipCoinSimple.deploy();
  
  await flipCoin.waitForDeployment();
  
  const address = await flipCoin.getAddress();
  console.log("FlipCoinSimple desplegado en:", address);
  
  // Verificar el despliegue
  console.log("Verificando contrato...");
  const owner = await flipCoin.owner();
  const houseFee = await flipCoin.houseFeeBP();
  
  console.log("Owner:", owner);
  console.log("House Fee (BP):", houseFee.toString());
  console.log("Next Bet ID:", (await flipCoin.nextBetId()).toString());
  
  return address;
}

main()
  .then((address) => {
    console.log("Despliegue completado exitosamente!");
    console.log("Dirección del contrato:", address);
    process.exit(0);
  })
  .catch((error) => {
    console.error("Error en el despliegue:", error);
    process.exit(1);
  });
