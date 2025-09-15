# Flujo de Doble Condición ZK - Flip-a-Coin

## 🎯 **Objetivo**
Implementar la **doble condición ZK** que centraliza la verificación en una sola prueba, demostrando simultáneamente:
1. **Conocimiento de ambas preimágenes** comprometidas
2. **Verificación directa del XOR** entre ambas partes = resultado

## 🔄 **Flujo Completo**

### **Fase 1: Commit (Off-chain)**
```
Jugador:
├── Genera preimagen de 512 bits (16 uint32)
├── Calcula hash(preimagen) = commitment
└── Envía commitment al contrato

Casa:
├── Genera preimagen de 512 bits (16 uint32)  
├── Calcula hash(preimagen) = commitment
└── Envía commitment al contrato
```

### **Fase 2: VRF (On-chain)**
```
Casa:
├── Solicita VRF para índice aleatorio (0-511)
├── Recibe índice i del VRF
└── Índice se almacena en el contrato
```

### **Fase 3: Generación ZK (Off-chain)**
```
Jugador + Casa:
├── Usan sus preimágenes + índice i
├── Generan prueba ZK que demuestra:
│   ├── Conocimiento de su preimagen
│   ├── Conocimiento de la preimagen del oponente
│   └── Que XOR(bitJugador[i], bitCasa[i]) = resultado
└── Envían prueba ZK al contrato
```

### **Fase 4: Verificación ZK (On-chain)**
```
Contrato:
├── Recibe prueba ZK de doble condición
├── Verifica simultáneamente:
│   ├── Conocimiento de preimagen del jugador
│   ├── Conocimiento de preimagen de la casa
│   └── XOR(bitJugador[i], bitCasa[i]) = resultado
├── Si verificación exitosa:
│   ├── Calcula XOR final
│   ├── Determina ganador
│   └── Distribuye fondos
└── Si falla: Rechaza la transacción
```

## 🧮 **Matemáticas del Circuito**

### **Inputs del Circuito:**
```circom
signal input playerPreimage[16];      // Preimagen jugador (512 bits)
signal input playerPreimageHash;      // Hash del jugador
signal input housePreimage[16];       // Preimagen casa (512 bits)
signal input housePreimageHash;       // Hash de la casa
signal input bitPosition;             // Índice i (0-511)
signal input expectedResult;          // Resultado esperado (0 o 1)
```

### **Constraints del Circuito:**
```circom
// 1. Verificar conocimiento de preimagen del jugador
playerCalculatedHash === playerPreimageHash;

// 2. Verificar conocimiento de preimagen de la casa
houseCalculatedHash === housePreimageHash;

// 3. Extraer bits en posición i
playerBit = playerPreimage[bitPosition/32] >> (bitPosition%32) & 1;
houseBit = housePreimage[bitPosition/32] >> (bitPosition%32) & 1;

// 4. Calcular XOR
xorResult = playerBit ^ houseBit;

// 5. Verificar que XOR = resultado esperado
xorResult === expectedResult;
```

## 🎭 **Ventajas de la Doble Condición ZK**

### **✅ Ventajas:**
1. **Centralización**: Una sola prueba ZK verifica todo
2. **Eficiencia**: Menos verificaciones on-chain
3. **Seguridad**: Imposible falsificar el resultado
4. **Transparencia**: El resultado es verificable públicamente
5. **Atomicidad**: Todo se verifica en una sola transacción

### **⚠️ Desafíos:**
1. **Complejidad**: Circuito más complejo
2. **Gas**: Verificación ZK más costosa
3. **Coordinación**: Ambas partes deben generar la prueba
4. **Tamaño**: Prueba ZK más grande

## 🔧 **Implementación Técnica**

### **Contrato Principal:**
```solidity
function settleBetWithDualZK(
    uint256 _betId,
    uint32[16] calldata _playerPreimage,
    uint32[16] calldata _housePreimage,
    uint8 _expectedResult,
    bytes calldata _zkProof
) external {
    // Verificar prueba ZK de doble condición
    require(
        dualZKVerifier.verifyDualProof(
            _playerPreimage,
            bet.playerCommit,
            _housePreimage,
            bet.houseCommit,
            bet.randomIndex,
            _expectedResult,
            _zkProof
        ),
        "Invalid dual ZK proof"
    );
    
    // Calcular XOR y determinar ganador
    uint8 playerBit = _getBitAt(_playerPreimage, bet.randomIndex);
    uint8 houseBit = _getBitAt(_housePreimage, bet.randomIndex);
    uint8 result = playerBit ^ houseBit;
    
    // Distribuir fondos según resultado
    _distributeFunds(_betId, result);
}
```

### **Verificador ZK:**
```solidity
function verifyDualProof(
    uint32[16] calldata _playerPreimage,
    bytes32 _playerPreimageHash,
    uint32[16] calldata _housePreimage,
    bytes32 _housePreimageHash,
    uint256 _bitPosition,
    uint8 _expectedResult,
    bytes calldata _zkProof
) external pure returns (bool) {
    // Verificar conocimiento de ambas preimágenes
    // Verificar XOR = resultado esperado
    // Verificar prueba ZK
}
```

## 🎯 **Resultado Final**

El sistema implementa la **doble condición ZK** que:

1. **Demuestra conocimiento** de ambas preimágenes sin revelarlas
2. **Verifica directamente** que XOR(bitJugador[i], bitCasa[i]) = resultado
3. **Centraliza la verificación** en una sola prueba ZK
4. **Garantiza la integridad** del juego de forma transparente y verificable

Esto cumple exactamente el diagrama que mencionaste, donde el **Verificador ZK on-chain** recibe las pruebas de ambas partes y verifica simultáneamente el conocimiento de las preimágenes y el resultado del XOR.
