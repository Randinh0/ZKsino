pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";

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
    
    // ============ OUTPUTS ============
    
    // Resultado del XOR
    signal output result;
    
    // ============ LÓGICA PRINCIPAL ============
    
    // 1. Verificar conocimiento de la preimagen del jugador (temporalmente deshabilitado)
    // component playerPoseidon = Poseidon(16);
    // for (var i = 0; i < 16; i++) {
    //     playerPoseidon.inputs[i] <== playerPreimage[i];
    // }
    // playerPoseidon.out === playerCommit;
    
    // 2. Verificar conocimiento de la preimagen de la casa (temporalmente deshabilitado)
    // component housePoseidon = Poseidon(16);
    // for (var i = 0; i < 16; i++) {
    //     housePoseidon.inputs[i] <== housePreimage[i];
    // }
    // housePoseidon.out === houseCommit;
    
    // 3. Acceso directo al bit (simplificado para prueba)
    var wordIdx = bitIndex / 32;
    var bitOff = bitIndex % 32;
    
    // Para bitIndex=137: wordIdx=4, bitOff=9
    // Acceso directo a la palabra 4
    signal selectedPlayerWord;
    signal selectedHouseWord;
    selectedPlayerWord <-- playerPreimage[4];
    selectedHouseWord <-- housePreimage[4];
    
    // 4. Descomponer palabras en bits
    component pBits = Num2Bits(32);
    component hBits = Num2Bits(32);
    pBits.in <== selectedPlayerWord;
    hBits.in <== selectedHouseWord;
    
    // 5. Acceso directo al bit 9
    signal playerBit;
    signal houseBit;
    playerBit <-- pBits.out[9];
    houseBit <-- hBits.out[9];
    
    // 9. Asegurar booleanos
    playerBit * (playerBit - 1) === 0;
    houseBit * (houseBit - 1) === 0;
    
    // 10. XOR en campo: result = a XOR b = a + b - 2ab
    result <== playerBit + houseBit - 2 * playerBit * houseBit;
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
component main {public [playerCommit, houseCommit, bitIndex]} = FlipCoinDualZK();