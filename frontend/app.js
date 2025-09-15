// Configuración del contrato
const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Dirección del contrato desplegado
const CONTRACT_ABI = [
    {
        "inputs": [],
        "stateMutability": "nonpayable",
        "type": "constructor"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "uint256",
                "name": "id",
                "type": "uint256"
            },
            {
                "indexed": true,
                "internalType": "address",
                "name": "player",
                "type": "address"
            },
            {
                "indexed": false,
                "internalType": "uint256",
                "name": "amount",
                "type": "uint256"
            }
        ],
        "name": "BetPlaced",
        "type": "event"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "uint256",
                "name": "id",
                "type": "uint256"
            },
            {
                "indexed": true,
                "internalType": "address",
                "name": "player",
                "type": "address"
            },
            {
                "indexed": false,
                "internalType": "bool",
                "name": "won",
                "type": "bool"
            }
        ],
        "name": "BetResolved",
        "type": "event"
    },
    {
        "inputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "name": "bets",
        "outputs": [
            {
                "internalType": "address",
                "name": "player",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "amount",
                "type": "uint256"
            },
            {
                "internalType": "uint256",
                "name": "nonce",
                "type": "uint256"
            },
            {
                "internalType": "bool",
                "name": "resolved",
                "type": "bool"
            },
            {
                "internalType": "bool",
                "name": "won",
                "type": "bool"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "houseFeeBP",
        "outputs": [
            {
                "internalType": "uint16",
                "name": "",
                "type": "uint16"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "nextBetId",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "owner",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "uint256",
                "name": "clientNonce",
                "type": "uint256"
            }
        ],
        "name": "placeBet",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "id",
                "type": "uint256"
            }
        ],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "withdraw",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "stateMutability": "payable",
        "type": "receive"
    }
];

// Variables globales
let provider;
let signer;
let contract;
let userAddress;

// Inicialización
window.addEventListener('load', async () => {
    // Verificar si MetaMask está instalado
    if (typeof window.ethereum !== 'undefined') {
        provider = new ethers.providers.Web3Provider(window.ethereum);
        await initializeApp();
    } else {
        showStatus('Por favor instala MetaMask para usar esta aplicación', 'error');
    }
});

async function initializeApp() {
    try {
        // Solicitar acceso a la cuenta
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        
        signer = provider.getSigner();
        userAddress = await signer.getAddress();
        
        // Crear instancia del contrato
        contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
        
        // Actualizar UI
        updateWalletInfo();
        showGameSection();
        
        // Escuchar eventos del contrato
        setupEventListeners();
        
        showStatus('Wallet conectada exitosamente!', 'success');
        
    } catch (error) {
        console.error('Error conectando wallet:', error);
        showStatus('Error conectando wallet: ' + error.message, 'error');
    }
}

function updateWalletInfo() {
    document.getElementById('walletAddress').textContent = 
        userAddress.substring(0, 6) + '...' + userAddress.substring(38);
    document.getElementById('walletInfo').classList.remove('hidden');
}

async function updateWalletBalance() {
    try {
        const balance = await provider.getBalance(userAddress);
        const balanceInEth = ethers.utils.formatEther(balance);
        document.getElementById('walletBalance').textContent = 
            parseFloat(balanceInEth).toFixed(4) + ' ETH';
    } catch (error) {
        console.error('Error obteniendo balance:', error);
    }
}

function showGameSection() {
    document.getElementById('gameSection').classList.remove('hidden');
    updateWalletBalance();
}

function setupEventListeners() {
    // Escuchar evento BetPlaced
    contract.on('BetPlaced', (id, player, amount, event) => {
        if (player.toLowerCase() === userAddress.toLowerCase()) {
            showStatus(`Apuesta #${id.toString()} colocada por ${ethers.utils.formatEther(amount)} ETH`, 'info');
        }
    });
    
    // Escuchar evento BetResolved
    contract.on('BetResolved', (id, player, won, event) => {
        if (player.toLowerCase() === userAddress.toLowerCase()) {
            showBetResult(id, won);
        }
    });
}

async function placeBet() {
    try {
        const betAmount = document.getElementById('betAmount').value;
        const clientNonce = document.getElementById('clientNonce').value;
        
        if (!betAmount || betAmount <= 0) {
            showStatus('Por favor ingresa una cantidad válida', 'error');
            return;
        }
        
        if (!clientNonce) {
            showStatus('Por favor ingresa un nonce', 'error');
            return;
        }
        
        const amountInWei = ethers.utils.parseEther(betAmount);
        
        // Deshabilitar botón durante la transacción
        const button = document.getElementById('placeBet');
        button.disabled = true;
        button.textContent = 'Procesando...';
        
        showStatus('Enviando transacción...', 'info');
        
        // Llamar al contrato
        const tx = await contract.placeBet(clientNonce, {
            value: amountInWei
        });
        
        showStatus('Transacción enviada. Esperando confirmación...', 'info');
        
        // Esperar confirmación
        await tx.wait();
        
        showStatus('Transacción confirmada!', 'success');
        
        // Actualizar balance
        updateWalletBalance();
        
    } catch (error) {
        console.error('Error en placeBet:', error);
        showStatus('Error: ' + error.message, 'error');
    } finally {
        // Rehabilitar botón
        const button = document.getElementById('placeBet');
        button.disabled = false;
        button.textContent = '🎲 Apostar';
    }
}

function showBetResult(betId, won) {
    const coinElement = document.getElementById('coinResult');
    const resultText = document.getElementById('resultText');
    const betDetails = document.getElementById('betDetails');
    const betResult = document.getElementById('betResult');
    
    // Mostrar resultado visual
    if (won) {
        coinElement.textContent = '🟢';
        resultText.textContent = '¡Ganaste!';
        resultText.style.color = '#2ecc71';
    } else {
        coinElement.textContent = '🔴';
        resultText.textContent = 'Perdiste';
        resultText.style.color = '#e74c3c';
    }
    
    betDetails.textContent = `Apuesta #${betId.toString()}`;
    betResult.classList.remove('hidden');
    
    // Actualizar balance
    updateWalletBalance();
}

function generateNonce() {
    const nonce = Math.floor(Math.random() * 1000000);
    document.getElementById('clientNonce').value = nonce;
}

function showStatus(message, type) {
    const statusElement = document.getElementById('status');
    statusElement.textContent = message;
    statusElement.className = `status ${type}`;
    statusElement.classList.remove('hidden');
    
    // Ocultar después de 5 segundos para mensajes de éxito
    if (type === 'success') {
        setTimeout(() => {
            statusElement.classList.add('hidden');
        }, 5000);
    }
}

// Función para conectar wallet (botón)
document.getElementById('connectWallet').addEventListener('click', async () => {
    if (typeof window.ethereum !== 'undefined') {
        try {
            await window.ethereum.request({ method: 'eth_requestAccounts' });
            await initializeApp();
        } catch (error) {
            console.error('Error conectando wallet:', error);
            showStatus('Error conectando wallet: ' + error.message, 'error');
        }
    } else {
        showStatus('Por favor instala MetaMask', 'error');
    }
});

// Actualizar balance cada 10 segundos
setInterval(updateWalletBalance, 10000);
