pragma circom 2.0.0;

include "node_modules/circomlib/circuits/poseidon.circom";

/**
 * @title FlipCoinDualZK
 * @dev Circuito ZK que implementa la doble condición:
 * 1. Conocimiento de ambas preimágenes comprometidas
 * 2. Verificación directa del XOR entre ambas partes = resultado
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
    
    // ============ OUTPUTS ============
    
    // Resultado del XOR
    signal output result;
    
    // ============ LÓGICA PRINCIPAL ============
    
    // 1. Verificar conocimiento de la preimagen del jugador
    component playerPoseidon = Poseidon(16);
    for (var i = 0; i < 16; i++) {
        playerPoseidon.inputs[i] <== playerPreimage[i];
    }
    playerPoseidon.out === playerCommit;
    
    // 2. Verificar conocimiento de la preimagen de la casa
    component housePoseidon = Poseidon(16);
    for (var i = 0; i < 16; i++) {
        housePoseidon.inputs[i] <== housePreimage[i];
    }
    housePoseidon.out === houseCommit;
    
    // 3. Descomponer bitIndex
    var wordIdx = bitIndex / 32;
    var bitOff = bitIndex % 32;
    
    // 4. Selectores one-hot para elegir palabra (16) y bit (32)
    signal wSel[16];   // booleanos, sum wSel = 1, sum i*wSel[i] = wordIdx
    signal bSel[32];   // booleanos, sum bSel = 1, sum j*bSel[j] = bitOff
    for (var i = 0; i < 16; i++) {
        wSel[i] * (wSel[i] - 1) === 0;
    }
    for (var j = 0; j < 32; j++) {
        bSel[j] * (bSel[j] - 1) === 0;
    }
    sum(wSel) === 1;
    sum(bSel) === 1;
    sum(i * wSel[i]) === wordIdx;
    sum(j * bSel[j]) === bitOff;
    
    // 5. Seleccionar palabra de jugador y casa con wSel
    var selectedPlayerWord = 0;
    var selectedHouseWord = 0;
    for (var i = 0; i < 16; i++) {
        selectedPlayerWord += wSel[i] * playerPreimage[i];
        selectedHouseWord += wSel[i] * housePreimage[i];
    }
    
    // 6. Descomponer palabras en bits y seleccionar bit con bSel
    component pBits = Num2Bits(32);
    component hBits = Num2Bits(32);
    pBits.in <== selectedPlayerWord;
    hBits.in <== selectedHouseWord;
    
    var playerBit = 0;
    var houseBit = 0;
    for (var j = 0; j < 32; j++) {
        playerBit += bSel[j] * pBits.out[j];
        houseBit += bSel[j] * hBits.out[j];
    }
    
    // 7. XOR en campo: result = a XOR b = a + b - 2ab
    playerBit * (playerBit - 1) === 0;
    houseBit * (houseBit - 1) === 0;
    result <== playerBit + houseBit - 2 * playerBit * houseBit;
}

// Función auxiliar para convertir uint32 a bits
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
component main {public [playerCommit, houseCommit, bitIndex]} = FlipCoinDualZK();
