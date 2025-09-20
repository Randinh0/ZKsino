# Claves ZK

Este directorio contiene las claves necesarias para generar y verificar pruebas ZK del circuito FlipCoinDualZK.

## Archivos

- `flip_coin_dual_zk_final_0001.zkey` - Clave de prueba (proving key)
- `verification_key_final.json` - Clave de verificación (verification key)

## Uso

Estas claves son utilizadas automáticamente por los scripts en `scripts/`:

```bash
# Generar y verificar prueba
node scripts/generate_and_verify_proof.js

# Script rápido
node scripts/quick_proof.js
```

## Notas

- Las claves se generaron con Power of Tau 14 (pot14_final.ptau)
- Son específicas para el circuito FlipCoinDualZK actual
- Si se modifica el circuito, será necesario regenerar las claves
