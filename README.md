# ZKsino - Casino Descentralizado

Una aplicación de casino descentralizada que permite apostar en un juego de cara o cruz usando contratos inteligentes.

## 🎯 Características

- **Contrato Inteligente**: FlipCoinSimple.sol - Juego de cara o cruz con comisión de casa del 2%
- **Frontend Web**: Interfaz sencilla para interactuar con el contrato
- **Despliegue Automatizado**: Scripts para desplegar en redes locales y de prueba

## 🚀 Instalación y Configuración

### Prerrequisitos
- Node.js (v16 o superior)
- MetaMask instalado en el navegador
- Git

### Instalación
```bash
# Clonar el repositorio
git clone https://github.com/Randinh0/ZKsino.git
cd ZKsino

# Instalar dependencias
npm install

# Compilar contratos
npm run compile
```

## 🎮 Cómo Usar

### 1. Iniciar la Red Local
```bash
# Terminal 1: Iniciar nodo local
npm run start
```

### 2. Desplegar el Contrato
```bash
# Terminal 2: Desplegar contrato
npm run deploy
```

### 3. Configurar MetaMask
1. Abre MetaMask
2. Cambia a "Red Local" o agrega una nueva red:
   - **RPC URL**: `http://localhost:8545`
   - **Chain ID**: `31337`
   - **Símbolo**: `ETH`

3. Importa una cuenta usando la clave privada de Hardhat:
   ```
   0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```

### 4. Abrir el Frontend
1. Abre `frontend/index.html` en tu navegador
2. Conecta MetaMask
3. ¡Comienza a apostar!

## 🎲 Cómo Jugar

1. **Conecta tu Wallet**: Haz clic en "Conectar MetaMask"
2. **Ingresa la Cantidad**: Especifica cuánto ETH quieres apostar
3. **Genera un Nonce**: Usa el botón "Generar Nonce Aleatorio" o ingresa uno manual
4. **Apostar**: Haz clic en "🎲 Apostar"
5. **Ver Resultado**: El contrato resolverá automáticamente y mostrará si ganaste o perdiste

## 📋 Estructura del Proyecto

```
ZKsino/
├── contracts/
│   └── FlipCoinSimple.sol      # Contrato principal
├── scripts/
│   └── deploy.js               # Script de despliegue
├── test/
│   └── FlipCoinSimple.test.js  # Pruebas unitarias
├── frontend/
│   ├── index.html              # Interfaz web
│   └── app.js                  # Lógica JavaScript
├── hardhat.config.js           # Configuración de Hardhat
├── demo-complete.sh            # Script de demostración
└── package.json               # Dependencias y scripts
```

## 🔧 Scripts Disponibles

- `npm run compile` - Compilar contratos
- `npm run deploy` - Desplegar en red hardhat
- `npm run deploy:localhost` - Desplegar en localhost
- `npm run start` - Iniciar nodo local
- `npm test` - Ejecutar tests

## ⚠️ Consideraciones de Seguridad

**IMPORTANTE**: Este contrato usa una fuente de aleatoriedad insegura para fines de demostración. En producción, deberías usar:

- **Chainlink VRF** para aleatoriedad verificable
- **Commit-Reveal schemes** para mayor seguridad
- **Oracles externos** para datos aleatorios

## 🎯 Flujo de la Aplicación

```mermaid
flowchart TD
    U[Usuario - Wallet] -->|1. placeBet(amount)| DAppFrontend
    DAppFrontend -->|2. tx: placeBet()| SmartContract
    SmartContract -->|3a. Nivel1: compute keccak| SmartContract
    SmartContract -->|5. payout / emit event| DAppFrontend
    DAppFrontend -->|6. show resultado| U
```

## 🛠️ Tecnologías Utilizadas

- **Solidity** ^0.8.20
- **Hardhat** ^2.26.3
- **Ethers.js** ^5.7.2
- **OpenZeppelin** ^5.4.0
- **HTML/CSS/JavaScript** (Frontend)

## 📝 Notas de Desarrollo

- El contrato se despliega automáticamente en la dirección: `0x5FbDB2315678afecb367f032d93F642f64180aa3`
- La comisión de la casa es del 2% (200 basis points)
- Los eventos se escuchan automáticamente para mostrar resultados
- El frontend se actualiza en tiempo real con el balance de la wallet

## 🚀 Próximos Pasos

- [ ] Integrar Chainlink VRF para aleatoriedad segura
- [ ] Agregar más juegos de casino
- [ ] Implementar sistema de tokens nativos
- [ ] Agregar pruebas unitarias completas
- [ ] Desplegar en redes de prueba (Goerli, Sepolia)
