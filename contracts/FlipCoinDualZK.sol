// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "./IVerifier.sol";

/**
 * @title FlipCoinDualZK
 * @dev Contrato principal para Flip-a-Coin con doble condición ZK
 * @notice Implementa commit-reveal con VRF y verificación ZK centralizada
 */
contract FlipCoinDualZK is VRFConsumerBaseV2, ReentrancyGuard, Ownable {
    
    // ============ ESTRUCTURAS ============
    
    struct Bet {
        address player;
        address house;
        uint256 amount;
        bytes32 playerCommit;
        bytes32 houseCommit;
        uint256 randomIndex;
        bool settled;
        uint256 timestamp;
    }
    
    struct VRFRequest {
        uint256 betId;
        bool fulfilled;
    }
    
    // ============ VARIABLES DE ESTADO ============
    
    uint256 public nextBetId;
    uint256 public houseFee; // Fee de la casa en basis points (100 = 1%)
    uint256 public minBetAmount;
    uint256 public maxBetAmount;
    
    mapping(uint256 => Bet) public bets;
    mapping(uint256 => VRFRequest) public vrfRequests;
    mapping(address => uint256) public pendingWithdrawals;
    
    // Verificador Groth16 generado por snarkjs (interfaz)
    IVerifier public immutable verifier;
    
    // VRF
    VRFCoordinatorV2Interface public immutable COORDINATOR;
    bytes32 public immutable keyHash;
    uint64 public subscriptionId;
    uint32 public constant callbackGasLimit = 100000;
    uint16 public constant requestConfirmations = 3;
    uint32 public constant numWords = 1;
    
    // ============ EVENTOS ============
    
    event BetCreated(uint256 indexed betId, address indexed player, address indexed house, uint256 amount);
    event PlayerCommitted(uint256 indexed betId, address indexed player, bytes32 commit);
    event HouseCommitted(uint256 indexed betId, address indexed house, bytes32 commit);
    event VRFRequested(uint256 indexed betId, uint256 requestId);
    event VRFFulfilled(uint256 indexed betId, uint256 requestId, uint256 randomIndex);
    event BetSettled(uint256 indexed betId, address indexed winner, uint256 payout, uint8 playerBit, uint8 houseBit, uint8 result);
    event FundsWithdrawn(address indexed user, uint256 amount);
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint256 _houseFee,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        address _verifier
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        houseFee = _houseFee;
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;
        verifier = IVerifier(_verifier);
    }
    
    // ============ FUNCIONES PRINCIPALES ============
    
    /**
     * @dev Crear una nueva apuesta
     * @param _house Dirección de la casa
     * @param _playerCommit Hash de la preimagen del jugador
     */
    function createBet(address _house, bytes32 _playerCommit) external payable nonReentrant {
        require(_house != address(0) && _house != msg.sender, "Invalid house address");
        require(_playerCommit != bytes32(0), "Invalid player commit");
        require(msg.value >= minBetAmount, "Bet below minimum");
        require(msg.value <= maxBetAmount, "Bet above maximum");
        
        uint256 betId = nextBetId++;
        
        bets[betId] = Bet({
            player: msg.sender,
            house: _house,
            amount: msg.value,
            playerCommit: _playerCommit,
            houseCommit: bytes32(0),
            randomIndex: 0,
            settled: false,
            timestamp: block.timestamp
        });
        
        emit BetCreated(betId, msg.sender, _house, msg.value);
        emit PlayerCommitted(betId, msg.sender, _playerCommit);
    }
    
    /**
     * @dev Crear apuesta con ambos commits en una sola transacción (OPTIMIZADO)
     * @param _house Dirección de la casa
     * @param _playerCommit Hash de la preimagen del jugador
     * @param _houseCommit Hash de la preimagen de la casa
     */
    function createBetWithCommits(address _house, bytes32 _playerCommit, bytes32 _houseCommit) external payable nonReentrant {
        require(_house != address(0) && _house != msg.sender, "Invalid house address");
        require(_playerCommit != bytes32(0), "Invalid player commit");
        require(_houseCommit != bytes32(0), "Invalid house commit");
        require(msg.value >= minBetAmount, "Bet below minimum");
        require(msg.value <= maxBetAmount, "Bet above maximum");
        
        uint256 betId = nextBetId++;
        
        // Generar randomIndex automáticamente para testing
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            betId,
            msg.sender,
            _house,
            block.timestamp,
            _playerCommit,
            _houseCommit
        ))) % 512;
        
        bets[betId] = Bet({
            player: msg.sender,
            house: _house,
            amount: msg.value,
            playerCommit: _playerCommit,
            houseCommit: _houseCommit,
            randomIndex: randomIndex,
            settled: false,
            timestamp: block.timestamp
        });
        
        emit BetCreated(betId, msg.sender, _house, msg.value);
        emit HouseCommitted(betId, _house, _houseCommit);
        emit VRFFulfilled(betId, 0, randomIndex);
    }
    
    /**
     * @dev La casa se compromete con su preimagen
     * @param _betId ID de la apuesta
     * @param _houseCommit Hash de la preimagen de la casa
     */
    function houseCommit(uint256 _betId, bytes32 _houseCommit) external {
        Bet storage bet = bets[_betId];
        require(bet.house == msg.sender || (bet.house == address(this) && bet.player == msg.sender), "Only house can commit");
        require(bet.houseCommit == bytes32(0), "House already committed");
        require(_houseCommit != bytes32(0), "Invalid house commit");
        
        bet.houseCommit = _houseCommit;
        emit HouseCommitted(_betId, bet.house, _houseCommit);
        
        // Solicitar VRF para índice aleatorio
        _requestVRF(_betId);
    }
    
    /**
     * @dev Resolver apuesta con prueba ZK Groth16 (puede ser llamada por cualquiera con prueba válida)
     * @param _betId ID de la apuesta
     * @param _pA Prueba A
     * @param _pB Prueba B
     * @param _pC Prueba C
     * @param _pubSignals Señales públicas [playerCommit, houseCommit, bitIndex, expectedResult]
     */
    function settleBetWithDualZK(
        uint256 _betId,
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external nonReentrant {
        Bet storage bet = bets[_betId];
        // Cualquiera puede liquidar con prueba ZK válida (trustless)
        // require(bet.player == msg.sender || bet.house == msg.sender, "Only player or house can settle");
        require(!bet.settled, "Bet already settled");
        require(bet.randomIndex > 0, "VRF not fulfilled yet");
        require(_pubSignals[3] <= 1, "Invalid expected result");

        // Validar señales públicas contra el estado
        require(_pubSignals[0] == uint256(bet.playerCommit), "Player commit mismatch");
        require(_pubSignals[1] == uint256(bet.houseCommit), "House commit mismatch");
        require(_pubSignals[2] == bet.randomIndex, "Bit index mismatch");

        // Verificar prueba Groth16
        require(verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK proof");

        bet.settled = true;

        uint8 result = uint8(_pubSignals[3]);

        // Determinar ganador y distribuir fondos
        address winner;
        uint256 payout;

        if (result == 1) {
            winner = bet.player;
            payout = bet.amount * 2;
        } else {
            winner = bet.house;
            payout = bet.amount + (bet.amount * houseFee / 10000);
        }

        pendingWithdrawals[winner] += payout;

        // Bits individuales no se exponen; solo el resultado
        emit BetSettled(_betId, winner, payout, 0, 0, result);
    }
    
    /**
     * @dev Retirar fondos pendientes
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        
        emit FundsWithdrawn(msg.sender, amount);
    }
    
    // ============ FUNCIONES VRF ============
    
    /**
     * @dev Solicitar VRF para índice aleatorio
     * @param _betId ID de la apuesta
     */
    function _requestVRF(uint256 _betId) internal {
        require(bets[_betId].houseCommit != bytes32(0), "House must commit first");
        
        // En modo test, usar aleatoriedad simulada
        if (block.chainid == 31337 || subscriptionId == 0) {
            _setRandomIndexForTest(_betId);
            return;
        }
        
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        
        vrfRequests[requestId] = VRFRequest({
            betId: _betId,
            fulfilled: false
        });
        
        emit VRFRequested(_betId, requestId);
    }
    
    /**
     * @dev Establecer índice aleatorio para testing
     * @param _betId ID de la apuesta
     */
    function _setRandomIndexForTest(uint256 _betId) internal {
        Bet storage bet = bets[_betId];
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            _betId,
            bet.player,
            bet.house,
            block.timestamp
        ))) % 512; // 0-511 para 512 bits
        
        bet.randomIndex = randomIndex;
        emit VRFFulfilled(_betId, 0, randomIndex);
    }
    
    /**
     * @dev Solo entorno local: fijar índice aleatorio para pruebas
     */
    function setRandomIndexForTest(uint256 _betId, uint256 _index) external {
        require(block.chainid == 31337 || block.chainid == 1337, "Only in local test");
        require(_index < 512, "Index out of range");
        Bet storage bet = bets[_betId];
        require(bet.player == msg.sender || bet.house == msg.sender || owner() == msg.sender, "Not authorized");
        bets[_betId].randomIndex = _index;
        emit VRFFulfilled(_betId, 0, _index);
    }
    
    /**
     * @dev Callback de VRF
     * @param requestId ID de la solicitud VRF
     * @param randomWords Array de números aleatorios
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        VRFRequest storage request = vrfRequests[requestId];
        require(!request.fulfilled, "Request already fulfilled");
        
        request.fulfilled = true;
        uint256 betId = request.betId;
        uint256 randomIndex = randomWords[0] % 512; // 0-511 para 512 bits
        
        bets[betId].randomIndex = randomIndex;
        
        emit VRFFulfilled(betId, requestId, randomIndex);
    }
    
    // ============ FUNCIONES DE LECTURA ============
    
    /**
     * @dev Obtener información de una apuesta
     */
    function getBetInfo(uint256 _betId) external view returns (
        address player,
        address house,
        uint256 amount,
        bytes32 playerCommit,
        bytes32 houseCommitHash,
        uint256 randomIndex,
        bool settled,
        uint256 timestamp
    ) {
        Bet memory bet = bets[_betId];
        return (
            bet.player,
            bet.house,
            bet.amount,
            bet.playerCommit,
            bet.houseCommit,
            bet.randomIndex,
            bet.settled,
            bet.timestamp
        );
    }
    
    // ============ FUNCIONES DE ADMINISTRACIÓN ============
    
    /**
     * @dev Actualizar fee de la casa
     * @param _newFee Nuevo fee en basis points
     */
    function updateHouseFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee too high"); // Máximo 10%
        houseFee = _newFee;
    }
    
    /**
     * @dev Actualizar límites de apuesta
     * @param _minBet Nuevo mínimo
     * @param _maxBet Nuevo máximo
     */
    function updateBetLimits(uint256 _minBet, uint256 _maxBet) external onlyOwner {
        require(_minBet > 0, "Invalid min bet");
        require(_maxBet > _minBet, "Invalid max bet");
        minBetAmount = _minBet;
        maxBetAmount = _maxBet;
    }
    
    /**
     * @dev Retiro de emergencia (solo owner)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        payable(owner()).transfer(balance);
    }
}
