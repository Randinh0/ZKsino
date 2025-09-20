# Scripts de Generación de Pruebas ZK

Este directorio contiene scripts para generar y verificar pruebas ZK del circuito FlipCoinDualZK.

## Scripts Disponibles

### `generate_and_verify_proof.js`
Script completo que:
1. 🎲 Genera datos de entrada aleatorios
2. 🔨 Compila el circuito Circom
3. 🔐 Genera una prueba ZK
4. ✅ Verifica la prueba
5. 📊 Muestra estadísticas

**Uso:**
```bash
node scripts/generate_and_verify_proof.js
```

### `quick_proof.js`
Script simplificado que ejecuta el proceso completo.

**Uso:**
```bash
node scripts/quick_proof.js
# o
./scripts/quick_proof.js
```

## Archivos Generados

Los scripts generan archivos en el directorio `temp/`:

- `input.json` - Datos de entrada para el circuito
- `proof.json` - Prueba ZK generada
- `public.json` - Señales públicas de la prueba
- `flip_coin_dual_zk.r1cs` - Restricciones del circuito
- `flip_coin_dual_zk.sym` - Símbolos del circuito
- `flip_coin_dual_zk_js/` - WASM del circuito
- `flip_coin_dual_zk_cpp/` - C++ del circuito

## Requisitos

- Node.js
- circom2 instalado globalmente
- snarkjs instalado
- Archivos de prueba ZK en `zk_proof_generated/`

## Notas

- El circuito actual está configurado para `bitIndex=137` (palabra 4, bit 9)
- La verificación Poseidon está temporalmente deshabilitada
- Los datos se generan aleatoriamente en cada ejecución
