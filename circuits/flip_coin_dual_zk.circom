pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/gates.circom";

/**
 * @title FlipCoinDualZK
 * @dev Circuito ZK que implementa la doble condición:
 * 1. Conocimiento de ambas preimágenes comprometidas (Poseidon)
 * 2. Verificación directa del XOR entre el bit seleccionado de ambas partes = resultado
 */
template FlipCoinDualZK() {
    // ============ INPUTS ============
    
    // Preimagen de 512 bits (16 uint32) del jugador
    signal input playerPreimage[16];
    
    // Preimagen de 512 bits (16 uint32) de la casa
    signal input housePreimage[16];
    
    // ============ PUBLIC INPUTS ============
    
    // Hash de la preimagen del jugador
    signal input playerCommit;
    
    // Hash de la preimagen de la casa
    signal input houseCommit;
    
    // Posición del bit a verificar (0-511)
    signal input bitIndex;
    
    // Resultado esperado del XOR (0 o 1)
    signal input expectedResult;
    
    // ============ OUTPUTS ============
    
    // Resultado del XOR
    signal output result;
    
    // ============ LÓGICA PRINCIPAL ============
    
    // 1. Verificar conocimiento de las preimágenes con Poseidon(16)
    component playerPoseidon = Poseidon(16);
    component housePoseidon = Poseidon(16);
    for (var i = 0; i < 16; i++) {
        playerPoseidon.inputs[i] <== playerPreimage[i];
        housePoseidon.inputs[i] <== housePreimage[i];
    }
    playerPoseidon.out === playerCommit;
    housePoseidon.out === houseCommit;
    
    // 2. Descomponer bitIndex (0..511) en 9 bits: [b0..b4]=bitOff (LSB), [b5..b8]=wordIdx
    component idxBits = Num2Bits(9);
    idxBits.in <== bitIndex;
    
    // Asegurar rango 0..511 implícito por Num2Bits(9)
    
    // 3. Construir valores wordIdx (0..15) y bitOff (0..31) a partir de bits
    var pow2;
    signal wordIdxVal;
    signal bitOffVal;
    
    var bitOffExpr = 0;
    pow2 = 1;
    for (var j = 0; j < 5; j++) {
        bitOffExpr += idxBits.out[j] * pow2;
        pow2 = pow2 + pow2;
    }
    bitOffVal <== bitOffExpr;
    
    var wordIdxExpr = 0;
    pow2 = 1;
    for (var k = 0; k < 4; k++) {
        wordIdxExpr += idxBits.out[5 + k] * pow2;
        pow2 = pow2 + pow2;
    }
    wordIdxVal <== wordIdxExpr;
    
    // 4. MUX para seleccionar la palabra [0..15] sin indexación dinámica
    signal selectedPlayerWord;
    signal selectedHouseWord;
    
    signal sel[16];
    signal tP[16];
    signal tH[16];
    var sumSel = 0;
    var sumIdx = 0;
    // bits de wordIdx
    signal wbits[4];
    for (var wb = 0; wb < 4; wb++) {
        wbits[wb] <== idxBits.out[5 + wb];
    }
    // Arrays de señales intermedias para selección de palabra
    signal c0[16];
    signal c1[16];
    signal c2[16];
    signal c3[16];
    signal t01[16];
    signal t23[16];
    for (var i2 = 0; i2 < 16; i2++) {
        // sel[i2] = AND over 4 bits (pairwise multiply to keep quadratic)
        if (((i2 >> 0) & 1) == 1) { c0[i2] <== wbits[0]; } else { c0[i2] <== 1 - wbits[0]; }
        if (((i2 >> 1) & 1) == 1) { c1[i2] <== wbits[1]; } else { c1[i2] <== 1 - wbits[1]; }
        if (((i2 >> 2) & 1) == 1) { c2[i2] <== wbits[2]; } else { c2[i2] <== 1 - wbits[2]; }
        if (((i2 >> 3) & 1) == 1) { c3[i2] <== wbits[3]; } else { c3[i2] <== 1 - wbits[3]; }
        t01[i2] <== c0[i2] * c1[i2];
        t23[i2] <== c2[i2] * c3[i2];
        sel[i2] <== t01[i2] * t23[i2];
        tP[i2] <== sel[i2] * playerPreimage[i2];
        tH[i2] <== sel[i2] * housePreimage[i2];
        sumSel += sel[i2];
        sumIdx += sel[i2] * i2;
    }
    sumSel === 1;
    wordIdxVal === sumIdx;
    
    var accP = 0;
    var accH = 0;
    for (var i3 = 0; i3 < 16; i3++) {
        accP += tP[i3];
        accH += tH[i3];
    }
    selectedPlayerWord <== accP;
    selectedHouseWord <== accH;
    
    // 5. Descomponer palabras en bits (LSB primero) para alinear con Solidity
    component pBits = Num2Bits(32);
    component hBits = Num2Bits(32);
    pBits.in <== selectedPlayerWord;
    hBits.in <== selectedHouseWord;
    
    // 6. MUX para seleccionar el bit [0..31]
    signal playerBit;
    signal houseBit;
    
    signal bitSel[32];
    signal tPB[32];
    signal tHB[32];
    var sumBitSel = 0;
    var sumBitIdx = 0;
    // bits de bitOff
    signal obits[5];
    for (var ob = 0; ob < 5; ob++) {
        obits[ob] <== idxBits.out[ob];
    }
    // Arrays de señales intermedias para selección de bit
    signal d0[32];
    signal d1[32];
    signal d2[32];
    signal d3[32];
    signal d4[32];
    signal u01[32];
    signal u23[32];
    signal u0123[32];
    for (var b = 0; b < 32; b++) {
        // bitSel[b] = AND over 5 bits via pairwise chain
        if (((b >> 0) & 1) == 1) { d0[b] <== obits[0]; } else { d0[b] <== 1 - obits[0]; }
        if (((b >> 1) & 1) == 1) { d1[b] <== obits[1]; } else { d1[b] <== 1 - obits[1]; }
        if (((b >> 2) & 1) == 1) { d2[b] <== obits[2]; } else { d2[b] <== 1 - obits[2]; }
        if (((b >> 3) & 1) == 1) { d3[b] <== obits[3]; } else { d3[b] <== 1 - obits[3]; }
        if (((b >> 4) & 1) == 1) { d4[b] <== obits[4]; } else { d4[b] <== 1 - obits[4]; }
        u01[b] <== d0[b] * d1[b];
        u23[b] <== d2[b] * d3[b];
        u0123[b] <== u01[b] * u23[b];
        bitSel[b] <== u0123[b] * d4[b];
        tPB[b] <== bitSel[b] * pBits.out[b];
        tHB[b] <== bitSel[b] * hBits.out[b];
        sumBitSel += bitSel[b];
        sumBitIdx += bitSel[b] * b;
    }
    // Un solo bit seleccionado y coincide con bitOffVal
    sumBitSel === 1;
    bitOffVal === sumBitIdx;
    
    var accPB = 0;
    var accHB = 0;
    for (var b2 = 0; b2 < 32; b2++) {
        accPB += tPB[b2];
        accHB += tHB[b2];
    }
    playerBit <== accPB;
    houseBit <== accHB;
    
    // 7. Asegurar booleanos
    playerBit * (playerBit - 1) === 0;
    houseBit * (houseBit - 1) === 0;
    
    // 8. XOR en campo y comprobar contra expectedResult
    result <== playerBit + houseBit - 2 * playerBit * houseBit;
    expectedResult * (expectedResult - 1) === 0;
    result === expectedResult;
}

// Conversión a bits con restricción de igualdad y booleanidad
// Nota: se usa <-- para el shift, y lc1 === in para atar los bits al valor
template Num2Bits(n) {
    signal input in;
    signal output out[n];
    
    var lc1 = 0;
    var e2 = 1;
    
    for (var i = 0; i < n; i++) {
        out[i] <-- (in >> i) & 1;
        out[i] * (out[i] - 1) === 0;
        lc1 += out[i] * e2;
        e2 = e2 + e2;
    }
    
    lc1 === in;
}

// Componente principal
component main {public [playerCommit, houseCommit, bitIndex, expectedResult]} = FlipCoinDualZK();