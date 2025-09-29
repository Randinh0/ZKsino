const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');
const circomlibjs = require('circomlibjs');

// Función para generar datos de entrada aleatorios
async function generateTestData() {
    console.log('🎲 Generando datos de prueba...');
    
    // Preimágenes aleatorias de 16 elementos (512 bits total)
    const playerPreimage = [];
    const housePreimage = [];
    
    for (let i = 0; i < 16; i++) {
        playerPreimage.push(Math.floor(Math.random() * 2**32).toString());
        housePreimage.push(Math.floor(Math.random() * 2**32).toString());
    }
    
    // Bit index (0-511). Usamos 137 por conveniencia de pruebas
    const bitIndex = 137;
    const wordIdx = Math.floor(bitIndex / 32);
    const bitOff = bitIndex % 32;
    
    // Calcular commits Poseidon (como BigInt decimal string)
    const poseidon = await circomlibjs.buildPoseidon();
    const playerCommitBI = poseidon.F.toObject(poseidon(playerPreimage.map(BigInt)));
    const houseCommitBI = poseidon.F.toObject(poseidon(housePreimage.map(BigInt)));
    
    // Calcular expectedResult = XOR de los bits seleccionados (LSB-first)
    const playerWord = BigInt(playerPreimage[wordIdx]);
    const houseWord = BigInt(housePreimage[wordIdx]);
    const playerBit = Number((playerWord >> BigInt(bitOff)) & 1n);
    const houseBit = Number((houseWord >> BigInt(bitOff)) & 1n);
    const expectedResult = (playerBit ^ houseBit).toString();
    
    // Crear input.json
    const inputData = {
        playerPreimage: playerPreimage.map(String),
        housePreimage: housePreimage.map(String),
        playerCommit: playerCommitBI.toString(),
        houseCommit: houseCommitBI.toString(),
        bitIndex: bitIndex.toString(),
        expectedResult
    };
    
    const inputPath = path.join(__dirname, '../temp/input.json');
    fs.mkdirSync(path.join(__dirname, '../temp'), { recursive: true });
    fs.writeFileSync(inputPath, JSON.stringify(inputData, null, 2));
    
    console.log('✅ Datos generados:');
    console.log(`   Player Preimage: [${playerPreimage.slice(0, 3).join(', ')}...] (16 elementos)`);
    console.log(`   House Preimage: [${housePreimage.slice(0, 3).join(', ')}...] (16 elementos)`);
    console.log(`   Bit Index: ${bitIndex} (palabra ${wordIdx}, bit ${bitOff})`);
    console.log(`   Expected Result (XOR): ${expectedResult}`);
    console.log(`   Archivo guardado en: ${inputPath}`);
    
    return inputPath;
}

// Función para compilar el circuito
function compileCircuit() {
    console.log('\n🔨 Compilando circuito...');
    
    try {
        const circuitDir = path.join(__dirname, '../circuits');
        
        // Cambiar al directorio circuits para compilar
        process.chdir(circuitDir);
        
        const compileCmd = `circom flip_coin_dual_zk.circom --r1cs --wasm --sym -l ../node_modules`;
        console.log(`   Ejecutando: ${compileCmd}`);
        
        execSync(compileCmd, { stdio: 'inherit' });
        
        console.log('✅ Circuito compilado exitosamente');
        return true;
        
    } catch (error) {
        console.error('❌ Error compilando circuito:', error.message);
        return false;
    }
}

// Función para generar la prueba ZK
function generateProof(inputPath) {
    console.log('\n🔐 Generando prueba ZK...');
    
    try {
        const wasmPath = path.join(__dirname, '../circuits/flip_coin_dual_zk_js/flip_coin_dual_zk.wasm');
    const zkeyPath = path.join(__dirname, '../zk_keys/flip_coin_dual_zk_final.zkey');
        const proofPath = path.join(__dirname, '../temp/proof.json');
        const publicPath = path.join(__dirname, '../temp/public.json');
        
        const proveCmd = `npx snarkjs groth16 fullprove "${inputPath}" "${wasmPath}" "${zkeyPath}" "${proofPath}" "${publicPath}"`;
        console.log(`   Ejecutando: ${proveCmd}`);
        
        execSync(proveCmd, { stdio: 'inherit' });
        
        console.log('✅ Prueba ZK generada exitosamente');
        console.log(`   Prueba: ${proofPath}`);
        console.log(`   Público: ${publicPath}`);
        
        return { proofPath, publicPath };
        
    } catch (error) {
        console.error('❌ Error generando prueba:', error.message);
        return null;
    }
}

// Función para verificar la prueba
function verifyProof(proofPath, publicPath) {
    console.log('\n✅ Verificando prueba ZK...');
    
    try {
        const verificationKeyPath = path.join(__dirname, '../zk_keys/verification_key_final.json');
        
        const verifyCmd = `npx snarkjs groth16 verify "${verificationKeyPath}" "${publicPath}" "${proofPath}"`;
        console.log(`   Ejecutando: ${verifyCmd}`);
        
        const result = execSync(verifyCmd, { encoding: 'utf8' });
        
        if (result.includes('OK!')) {
            console.log('✅ Prueba ZK verificada exitosamente');
            return true;
        } else {
            console.log('❌ La prueba ZK no es válida');
            return false;
        }
        
    } catch (error) {
        console.error('❌ Error verificando prueba:', error.message);
        return false;
    }
}

// Función para mostrar estadísticas de la prueba
function showProofStats(proofPath, publicPath) {
    console.log('\n📊 Estadísticas de la prueba:');
    
    try {
        const proof = JSON.parse(fs.readFileSync(proofPath, 'utf8'));
        const public = JSON.parse(fs.readFileSync(publicPath, 'utf8'));
        
        console.log(`   Tamaño de la prueba: ${JSON.stringify(proof).length} caracteres`);
        console.log(`   Señales públicas: ${public.length} elementos`);
        console.log(`   Señales públicas: [${public.join(', ')}]`);
        
    } catch (error) {
        console.log('   No se pudieron cargar las estadísticas');
    }
}

// Generar calldata Solidity para (a,b,c,publicSignals)
function generateSolidityCalldata(proofPath, publicPath) {
  console.log('\n🧾 Generando calldata para Solidity...');
  try {
    const outPath = path.join(__dirname, '../temp/solidity_calldata.txt');
    const cmd = `npx snarkjs zkey export soliditycalldata "${publicPath}" "${proofPath}"`;
    const output = execSync(cmd, { encoding: 'utf8' });
    fs.writeFileSync(outPath, output);
    console.log(`   ✅ Calldata guardado en: ${outPath}`);
    return outPath;
  } catch (e) {
    console.error('❌ Error generando calldata:', e.message);
    return null;
  }
}

// Función principal
async function main() {
    console.log('🚀 Iniciando generación y verificación de prueba ZK\n');
    
    try {
        // 1. Generar datos de entrada
        const inputPath = await generateTestData();
        
        // 2. Compilar circuito
        if (!compileCircuit()) {
            console.log('❌ Falló la compilación del circuito');
            process.exit(1);
        }
        
        // 3. Generar prueba ZK
        const proofFiles = generateProof(inputPath);
        if (!proofFiles) {
            console.log('❌ Falló la generación de la prueba');
            process.exit(1);
        }
        
        // 4. Verificar prueba
        const isValid = verifyProof(proofFiles.proofPath, proofFiles.publicPath);
        if (!isValid) {
            console.log('❌ La prueba no es válida');
            process.exit(1);
        }
        
    // 5. Mostrar estadísticas
        showProofStats(proofFiles.proofPath, proofFiles.publicPath);
    // 6. Calldata
    generateSolidityCalldata(proofFiles.proofPath, proofFiles.publicPath);
        
        console.log('\n🎉 ¡Proceso completado exitosamente!');
        console.log('📁 Archivos generados en: temp/');
        
    } catch (error) {
        console.error('❌ Error en el proceso:', error.message);
        process.exit(1);
    }
}

// Ejecutar si es llamado directamente
if (require.main === module) {
    main();
}

module.exports = { generateTestData, compileCircuit, generateProof, verifyProof };
