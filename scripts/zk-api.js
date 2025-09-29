const express = require('express');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const circomlibjs = require('circomlibjs');
const { ethers } = require('ethers');

const app = express();
const PORT = 3001;

// Configuración del contrato
const CONTRACT_ADDRESS = '0xa513E6E4b8f2a923D98304ec87F64353C4D5C853';
const HOUSE_PRIVATE_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'; // Segunda cuenta Hardhat
const RPC_URL = 'http://hardhat:8545';

// Configurar provider y wallet
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const houseWallet = new ethers.Wallet(HOUSE_PRIVATE_KEY, provider);

const CONTRACT_ABI = [
    "function settleBetWithDualZK(uint256 _betId, uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[4] calldata _pubSignals) external",
    "function getBetInfo(uint256 _betId) external view returns (address player, address house, uint256 amount, bytes32 playerCommit, bytes32 houseCommitHash, uint256 randomIndex, bool settled, uint256 timestamp)",
    "function setRandomIndexForTest(uint256 _betId, uint256 _index) external",
    "event BetSettled(uint256 indexed betId, address indexed winner, uint256 payout, uint8 playerBit, uint8 houseBit, uint8 result)"
];

const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, houseWallet);

app.use(express.json());
app.use(express.static('public'));

// CORS para permitir requests del frontend
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Content-Type');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    next();
});

// Endpoint para generar prueba ZK completa
app.post('/generate-proof', async (req, res) => {
    try {
        console.log('🎲 Generando prueba ZK...');
        
        const { playerPreimage, housePreimage, bitIndex, betId } = req.body;
        
        // Validar inputs
        if (!playerPreimage || !housePreimage || bitIndex === undefined) {
            return res.status(400).json({ error: 'Faltan parámetros requeridos' });
        }
        
        // Calcular commits con Poseidon
        const poseidon = await circomlibjs.buildPoseidon();
        const playerCommit = poseidon.F.toObject(poseidon(playerPreimage.map(x => BigInt(x)))).toString();
        const houseCommit = poseidon.F.toObject(poseidon(housePreimage.map(x => BigInt(x)))).toString();
        
        // Calcular expectedResult
        const wordIdx = Math.floor(bitIndex / 32);
        const bitOff = bitIndex % 32;
        const playerWord = BigInt(playerPreimage[wordIdx]);
        const houseWord = BigInt(housePreimage[wordIdx]);
        const playerBit = Number((playerWord >> BigInt(bitOff)) & 1n);
        const houseBit = Number((houseWord >> BigInt(bitOff)) & 1n);
        const expectedResult = (playerBit ^ houseBit).toString();
        
        // Crear input.json
        const inputData = {
            playerPreimage: playerPreimage.map(String),
            housePreimage: housePreimage.map(String),
            playerCommit,
            houseCommit,
            bitIndex: bitIndex.toString(),
            expectedResult
        };
        
        const inputPath = path.join(__dirname, '../temp/input.json');
        fs.mkdirSync(path.dirname(inputPath), { recursive: true });
        fs.writeFileSync(inputPath, JSON.stringify(inputData, null, 2));
        
        // Compilar circuito
        console.log('🔨 Compilando circuito...');
        const circuitDir = path.join(__dirname, '../circuits');
        process.chdir(circuitDir);
        
        try {
            execSync('circom flip_coin_dual_zk.circom --r1cs --wasm --sym -l ../node_modules', { stdio: 'pipe' });
        } catch (compileError) {
            console.log('⚠️ Circuito ya compilado o error menor:', compileError.message);
        }
        
        // Generar prueba
        console.log('🔐 Generando prueba...');
        const wasmPath = path.join(__dirname, '../circuits/flip_coin_dual_zk_js/flip_coin_dual_zk.wasm');
        const zkeyPath = path.join(__dirname, '../zk_keys/flip_coin_dual_zk_new.zkey');
        const proofPath = path.join(__dirname, '../temp/proof.json');
        const publicPath = path.join(__dirname, '../temp/public.json');
        
        execSync(`npx snarkjs groth16 fullprove "${inputPath}" "${wasmPath}" "${zkeyPath}" "${proofPath}" "${publicPath}"`, { stdio: 'pipe' });
        
        // Leer prueba y señales públicas
        const proof = JSON.parse(fs.readFileSync(proofPath, 'utf8'));
        const publicSignals = JSON.parse(fs.readFileSync(publicPath, 'utf8'));
        
        // Usar directamente los datos de la prueba (más simple y confiable)
        const a = [proof.pi_a[0], proof.pi_a[1]];
        const b = [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]];
        const c = [proof.pi_c[0], proof.pi_c[1]];
        
        // Filtrar señales públicas al formato esperado por el contrato: [playerCommit, houseCommit, bitIndex, expectedResult]
        // El circuito genera: [playerCommit, houseCommit, bitIndex, expectedResult] (4 elementos)
        const pubSignals = [
            playerCommit,
            houseCommit, 
            bitIndex.toString(),
            expectedResult.toString()
        ];
        
        console.log('✅ Prueba generada exitosamente');
        
        // Liquidar automáticamente la apuesta si se proporciona betId
        let settlementResult = null;
        if (betId !== undefined) {
            try {
                console.log('🔍 Verificando estado de la apuesta...');
                
                // Verificar si el randomIndex ya está establecido
                const betInfo = await contract.getBetInfo(betId);
                console.log('📊 Estado de la apuesta:', {
                    randomIndex: betInfo.randomIndex.toString(),
                    settled: betInfo.settled
                });
                
                // Si randomIndex es 0, necesitamos establecerlo manualmente (modo test)
                if (betInfo.randomIndex.toString() === '0') {
                    console.log('🎲 Estableciendo randomIndex para testing...');
                    const setRandomTx = await contract.setRandomIndexForTest(betId, bitIndex);
                    await setRandomTx.wait();
                    console.log('✅ RandomIndex establecido');
                }
                
                console.log('💰 Liquidando apuesta automáticamente...');
                
                const tx = await contract.settleBetWithDualZK(
                    betId,
                    [a[0], a[1]],
                    [[b[0][0], b[0][1]], [b[1][0], b[1][1]]],
                    [c[0], c[1]],
                    pubSignals
                );
                
                const receipt = await tx.wait();
                console.log(`✅ Apuesta ${betId} liquidada automáticamente! TX: ${tx.hash}`);
                
                settlementResult = {
                    txHash: tx.hash,
                    settled: true,
                    winner: expectedResult === '1' ? 'Jugador' : 'Casa',
                    result: expectedResult
                };
                
            } catch (error) {
                console.error('❌ Error liquidando apuesta:', error);
                settlementResult = {
                    settled: false,
                    error: error.message
                };
            }
        }
        
        res.json({
            success: true,
            proof: { a, b, c },
            publicSignals: pubSignals,
            calldata: { a, b, c, publicSignals: pubSignals },
            playerCommit,
            houseCommit,
            expectedResult,
            bitIndex,
            playerBit,
            houseBit,
            settlement: settlementResult
        });
        
    } catch (error) {
        console.error('❌ Error generando prueba:', error);
        res.status(500).json({ 
            error: 'Error generando prueba ZK', 
            details: error.message 
        });
    }
});

// Endpoint para calcular commit Poseidon
app.post('/calculate-commit', async (req, res) => {
    try {
        const { preimage } = req.body;
        
        if (!preimage || !Array.isArray(preimage) || preimage.length !== 16) {
            return res.status(400).json({ 
                success: false, 
                error: 'Preimage debe ser un array de 16 elementos' 
            });
        }
        
        // Calcular hash Poseidon usando circomlibjs
        const poseidon = await circomlibjs.buildPoseidon();
        const commit = poseidon.F.toObject(poseidon(preimage.map(x => BigInt(x)))).toString();
        
        res.json({
            success: true,
            commit: commit
        });
        
    } catch (error) {
        console.error('Error calculando commit:', error);
        res.status(500).json({ 
            success: false, 
            error: error.message 
        });
    }
});

// Endpoint para generar datos aleatorios
app.get('/generate-random-data', async (req, res) => {
    try {
        const playerPreimage = [];
        const housePreimage = [];
        
        for (let i = 0; i < 16; i++) {
            playerPreimage.push(Math.floor(Math.random() * 2**32).toString());
            housePreimage.push(Math.floor(Math.random() * 2**32).toString());
        }
        
        const bitIndex = Math.floor(Math.random() * 512);
        
        res.json({
            playerPreimage,
            housePreimage,
            bitIndex
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 ZK API corriendo en puerto ${PORT}`);
    console.log(`📡 Endpoints disponibles:`);
    console.log(`   POST /generate-proof - Generar prueba ZK`);
    console.log(`   POST /calculate-commit - Calcular commit Poseidon`);
    console.log(`   GET  /generate-random-data - Datos aleatorios`);
});
