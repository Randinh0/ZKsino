#!/bin/bash

echo "🎰 ZKsino Beta - Demo Completo"
echo "=============================="
echo ""

# Verificar que Node.js esté instalado
if ! command -v node &> /dev/null; then
    echo "❌ Node.js no está instalado. Por favor instala Node.js primero."
    exit 1
fi

# Verificar que npm esté instalado
if ! command -v npm &> /dev/null; then
    echo "❌ npm no está instalado. Por favor instala npm primero."
    exit 1
fi

echo "✅ Node.js y npm están instalados"
echo ""

# Instalar dependencias si es necesario
if [ ! -d "node_modules" ]; then
    echo "📦 Instalando dependencias..."
    npm install
    echo ""
fi

# Compilar contratos
echo "🔨 Compilando contratos..."
npm run compile
echo ""

# Desplegar contrato
echo "🚀 Desplegando contrato..."
npm run deploy
echo ""

# Ejecutar pruebas
echo "🧪 Ejecutando pruebas..."
npm test
echo ""

echo "🎯 Sistema listo! Ahora puedes:"
echo ""
echo "1️⃣  Iniciar la red local de Hardhat (en otra terminal):"
echo "    npm run start"
echo ""
echo "2️⃣  Abrir el frontend en tu navegador:"
echo "    http://localhost:3000"
echo ""
echo "3️⃣  Configurar MetaMask:"
echo "    - Red: Localhost 8545"
echo "    - Chain ID: 31337"
echo "    - Importar cuenta con clave: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
echo ""
echo "4️⃣  ¡Comenzar a apostar!"
echo ""
echo "📱 El frontend ya está corriendo en http://localhost:3000"
echo "⏹️  Presiona Ctrl+C para detener el servidor frontend"
echo ""

# Iniciar servidor frontend
echo "🌐 Iniciando servidor frontend..."
npm run serve

