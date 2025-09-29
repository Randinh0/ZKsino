#!/bin/sh

echo "🚀 Iniciando Hardhat local y desplegando contratos..."

# Iniciar Hardhat en background
npx hardhat node --hostname 0.0.0.0 &
HARDHAT_PID=$!

# Esperar a que Hardhat esté listo
echo "⏳ Esperando a que Hardhat esté listo..."
sleep 10

# Desplegar contratos
echo "📦 Desplegando contratos..."
npx hardhat run scripts/deploy.js --network localhost

# Mantener Hardhat corriendo
echo "✅ Hardhat local corriendo en puerto 8545"
echo "✅ Contratos desplegados"
echo "📋 Para ver logs: docker-compose logs -f hardhat"

wait $HARDHAT_PID
