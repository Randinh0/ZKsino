# ZKsino - Docker Setup

## 🐳 Desarrollo con Docker

Este setup mantiene corriendo constantemente:
- **Hardhat local** (puerto 8545) con contratos desplegados
- **Frontend** (puerto 3000) con interfaz web
- **ZK Generator** para generar pruebas

## 🚀 Comandos

### Iniciar todo el entorno
```bash
docker-compose up -d
```

### Ver logs
```bash
# Todos los servicios
docker-compose logs -f

# Solo Hardhat
docker-compose logs -f hardhat

# Solo Frontend
docker-compose logs -f frontend
```

### Parar servicios
```bash
docker-compose down
```

### Reconstruir imágenes
```bash
docker-compose build --no-cache
```

## 📋 Servicios

### 1. Hardhat (puerto 8545)
- Red local Hardhat
- Contratos desplegados automáticamente
- MockVerifier para desarrollo
- VRF mock habilitado

### 2. Frontend (puerto 3000)
- Interfaz web completa
- Conexión automática a Hardhat
- Generación de pruebas ZK
- Liquidación de apuestas

### 3. ZK Generator
- Herramientas para generar pruebas
- Acceso a scripts de Circom
- Volúmenes compartidos

## 🔧 Configuración

### Variables de entorno
- `REACT_APP_HARDHAT_URL`: URL de Hardhat (http://hardhat:8545)
- `REACT_APP_CONTRACT_ADDRESS`: Se actualiza automáticamente

### Volúmenes compartidos
- `./contracts` → Contratos Solidity
- `./zk_keys` → Claves ZK
- `./temp` → Archivos temporales de pruebas
- `./frontend` → Código del frontend

## 🎯 Flujo de desarrollo

1. **Iniciar entorno**: `docker-compose up -d`
2. **Abrir frontend**: http://localhost:3000
3. **Conectar MetaMask** a http://localhost:8545
4. **Crear apuesta** desde el frontend
5. **Generar prueba ZK** (automático o manual)
6. **Liquidar apuesta** con la prueba

## 🐛 Debugging

### Ver logs de Hardhat
```bash
docker-compose logs -f hardhat
```

### Entrar al contenedor ZK
```bash
docker-compose exec zk-generator sh
cd /app/scripts
node generate_and_verify_proof.js
```

### Verificar contratos desplegados
```bash
docker-compose exec hardhat cat /app/contract-addresses.json
```

## 📁 Estructura de archivos

```
ZKsino_beta/
├── docker-compose.yml
├── Dockerfile.hardhat
├── Dockerfile.frontend
├── Dockerfile.zk
├── contracts/
├── circuits/
├── scripts/
├── frontend/
├── zk_keys/
└── temp/
```

## ⚡ Comandos útiles

```bash
# Reiniciar solo un servicio
docker-compose restart hardhat

# Ver estado de contenedores
docker-compose ps

# Limpiar volúmenes
docker-compose down -v

# Reconstruir y reiniciar
docker-compose up --build -d
```
