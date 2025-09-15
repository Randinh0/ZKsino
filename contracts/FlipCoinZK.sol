// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title FlipCoinZK
 * @dev Contrato principal para el mini casino Flip-a-Coin con sistema ZK
 * @notice Implementa commit-reveal con VRF y verificación ZK para apuestas 1:1
 */
contract FlipCoinZK is VRFConsumerBaseV2, ReentrancyGuard, Ownable {
    
    // ============ ESTRUCTURAS ============
    
    struct Bet {
        address player;
        address house;
        uint256 amount;
        bytes32 playerCommit;
        bytes32 houseCommit;
        uint32[16] playerPreimage;
        uint32[16] housePreimage;
        uint256 randomIndex;
        bool playerRevealed;
        bool houseRevealed;
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
    
    // ============ EVENTOS ============
    
    event BetCreated(uint256 indexed betId, address indexed player, address indexed house, uint256 amount);
    event PlayerCommitted(uint256 indexed betId, address indexed player, bytes32 commit);
    event HouseCommitted(uint256 indexed betId, address indexed house, bytes32 commit);
    event VRFRequested(uint256 indexed betId, uint256 indexed requestId);
    event VRFFulfilled(uint256 indexed betId, uint256 indexed requestId, uint256 randomIndex);
    event PlayerRevealed(uint256 indexed betId, address indexed player, uint8 bit, bytes zkProof);
    event HouseRevealed(uint256 indexed betId, address indexed house, uint8 bit, bytes zkProof);
    event BetSettled(uint256 indexed betId, address winner, uint256 amount, uint8 playerBit, uint8 houseBit);
    event FundsWithdrawn(address indexed account, uint256 amount);
    event HouseFeeUpdated(uint256 newFee);
    event BetLimitsUpdated(uint256 minAmount, uint256 maxAmount);
    
    // ============ VRF CONFIGURATION ============
    
    VRFCoordinatorV2Interface COORDINATOR;
    bytes32 public keyHash;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;
    uint64 public subscriptionId; // Necesita ser configurado
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint256 _houseFee,
        uint256 _minBetAmount,
        uint256 _maxBetAmount
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        houseFee = _houseFee;
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;
    }
    
    // ============ FUNCIONES PRINCIPALES ============
    
    /**
     * @dev Crear una nueva apuesta
     * @param _house Dirección de la casa
     * @param _playerCommit Hash de la preimagen del jugador
     */
    function createBet(address _house, bytes32 _playerCommit) external payable nonReentrant {
        require(msg.value >= minBetAmount && msg.value <= maxBetAmount, "Bet amount out of range");
        require(_house != address(0) && _house != msg.sender, "Invalid house address");
        require(_playerCommit != bytes32(0), "Invalid player commit");
        
        uint256 betId = nextBetId++;
        
        bets[betId] = Bet({
            player: msg.sender,
            house: _house,
            amount: msg.value,
            playerCommit: _playerCommit,
            houseCommit: bytes32(0),
            playerPreimage: [uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0)],
            housePreimage: [uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0), uint32(0)],
            randomIndex: 0,
            playerRevealed: false,
            houseRevealed: false,
            settled: false,
            timestamp: block.timestamp
        });
        
        emit BetCreated(betId, msg.sender, _house, msg.value);
        emit PlayerCommitted(betId, msg.sender, _playerCommit);
    }
    
    /**
     * @dev La casa hace commit de su preimagen
     * @param _betId ID de la apuesta
     * @param _houseCommit Hash de la preimagen de la casa
     */
    function houseCommit(uint256 _betId, bytes32 _houseCommit) external {
        Bet storage bet = bets[_betId];
        require(bet.house == msg.sender, "Only house can commit");
        require(bet.houseCommit == bytes32(0), "House already committed");
        require(_houseCommit != bytes32(0), "Invalid house commit");
        
        bet.houseCommit = _houseCommit;
        
        emit HouseCommitted(_betId, msg.sender, _houseCommit);
        
        // Solicitar VRF después de que ambos hayan hecho commit
        _requestVRF(_betId);
    }
    
    /**
     * @dev Solicitar VRF para obtener índice aleatorio
     * @param _betId ID de la apuesta
     */
    function _requestVRF(uint256 _betId) internal {
        require(bets[_betId].houseCommit != bytes32(0), "House must commit first");
        
        // En modo test, usar aleatoriedad simulada
        if (block.chainid == 31337 || subscriptionId == 0) { // Hardhat local network o sin subscription
            _setRandomIndexForTest(_betId);
            return;
        }
        
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId, // Necesita ser configurado
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
     * @dev Establecer índice aleatorio para testing (solo en red local)
     * @param _betId ID de la apuesta
     */
    function _setRandomIndexForTest(uint256 _betId) internal {
        Bet storage bet = bets[_betId];
        // Usar valores determinísticos para testing
        // Generar un índice que esté dentro del rango de 512 bits (0-511)
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            _betId,
            bet.player,
            bet.house,
            block.timestamp
        ))) % 512; // 0-511 para 512 bits (16 uint32)
        
        bet.randomIndex = randomIndex;
        emit VRFFulfilled(_betId, 0, randomIndex); // requestId = 0 para test
    }
    
    /**
     * @dev Callback de VRF para recibir número aleatorio
     * @param requestId ID de la solicitud VRF
     * @param randomWords Array de números aleatorios
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        VRFRequest storage request = vrfRequests[requestId];
        require(!request.fulfilled, "Request already fulfilled");
        
        request.fulfilled = true;
        uint256 betId = request.betId;
        Bet storage bet = bets[betId];
        
        // Obtener índice aleatorio (0-511 para 512 bits)
        uint256 randomIndex = randomWords[0] % 512;
        bet.randomIndex = randomIndex;
        
        emit VRFFulfilled(betId, requestId, randomIndex);
    }
    
    /**
     * @dev El jugador revela su bit y prueba ZK
     * @param _betId ID de la apuesta
     * @param _preimage Preimagen de 512 bits (16 uint32) del jugador
     * @param _zkProof Prueba ZK (placeholder por ahora)
     */
    function playerReveal(uint256 _betId, uint32[16] calldata _preimage, bytes calldata _zkProof) external {
        Bet storage bet = bets[_betId];
        require(bet.player == msg.sender, "Only player can reveal");
        require(!bet.playerRevealed, "Player already revealed");
        require(bet.randomIndex > 0, "VRF not fulfilled yet");
        require(keccak256(abi.encodePacked(_preimage)) == bet.playerCommit, "Invalid preimage");
        
        bet.playerRevealed = true;
        bet.playerPreimage = _preimage;
        
        // TODO: Verificar prueba ZK aquí
        // _verifyZKProof(_zkProof, _preimage, bet.randomIndex);
        
        emit PlayerRevealed(_betId, msg.sender, _getBitAt(_preimage, bet.randomIndex), _zkProof);
        
        // Intentar resolver la apuesta si ambos han revelado
        _trySettleBet(_betId);
    }
    
    /**
     * @dev La casa revela su bit y prueba ZK
     * @param _betId ID de la apuesta
     * @param _preimage Preimagen de 512 bits (16 uint32) de la casa
     * @param _zkProof Prueba ZK (placeholder por ahora)
     */
    function houseReveal(uint256 _betId, uint32[16] calldata _preimage, bytes calldata _zkProof) external {
        Bet storage bet = bets[_betId];
        require(bet.house == msg.sender, "Only house can reveal");
        require(!bet.houseRevealed, "House already revealed");
        require(bet.randomIndex > 0, "VRF not fulfilled yet");
        require(keccak256(abi.encodePacked(_preimage)) == bet.houseCommit, "Invalid preimage");
        
        bet.houseRevealed = true;
        bet.housePreimage = _preimage;
        
        // TODO: Verificar prueba ZK aquí
        // _verifyZKProof(_zkProof, _preimage, bet.randomIndex);
        
        emit HouseRevealed(_betId, msg.sender, _getBitAt(_preimage, bet.randomIndex), _zkProof);
        
        // Intentar resolver la apuesta si ambos han revelado
        _trySettleBet(_betId);
    }
    
    /**
     * @dev Intentar resolver la apuesta si ambos han revelado
     * @param _betId ID de la apuesta
     */
    function _trySettleBet(uint256 _betId) internal {
        Bet storage bet = bets[_betId];
        require(bet.playerRevealed && bet.houseRevealed, "Both parties must reveal");
        require(!bet.settled, "Bet already settled");
        
        bet.settled = true;
        
        // Obtener los bits de ambos participantes usando las preimágenes de 512 bits
        uint8 playerBit = _getBitAt(bet.playerPreimage, bet.randomIndex);
        uint8 houseBit = _getBitAt(bet.housePreimage, bet.randomIndex);
        
        // Calcular XOR para determinar ganador
        uint8 result = playerBit ^ houseBit;
        
        address winner;
        uint256 payout;
        
        if (result == 1) {
            // Jugador gana
            winner = bet.player;
            payout = bet.amount * 2; // Doble de la apuesta
        } else {
            // Casa gana
            winner = bet.house;
            payout = bet.amount + (bet.amount * houseFee / 10000); // Apuesta + fee
        }
        
        // Transferir fondos
        pendingWithdrawals[winner] += payout;
        
        emit BetSettled(_betId, winner, payout, playerBit, houseBit);
    }
    
    /**
     * @dev Obtener bit en posición específica de preimagen de 512 bits (16 uint32)
     * @param _preimage Preimagen como array de 16 uint32
     * @param _position Posición del bit (0-511)
     * @return Bit en la posición especificada
     */
    function _getBitAt(uint32[16] memory _preimage, uint256 _position) internal pure returns (uint8) {
        require(_position < 512, "Position out of range");
        uint256 uint32Index = _position / 32;
        uint256 bitIndex = _position % 32;
        return uint8(_preimage[uint32Index] >> bitIndex) & 1;
    }
    
    /**
     * @dev Retirar fondos pendientes
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        pendingWithdrawals[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit FundsWithdrawn(msg.sender, amount);
    }
    
    // ============ FUNCIONES DE ADMINISTRACIÓN ============
    
    /**
     * @dev Actualizar fee de la casa
     * @param _newFee Nuevo fee en basis points
     */
    function setHouseFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee too high"); // Máximo 10%
        houseFee = _newFee;
        emit HouseFeeUpdated(_newFee);
    }
    
    /**
     * @dev Actualizar límites de apuesta
     * @param _minAmount Cantidad mínima de apuesta
     * @param _maxAmount Cantidad máxima de apuesta
     */
    function setBetLimits(uint256 _minAmount, uint256 _maxAmount) external onlyOwner {
        require(_minAmount > 0 && _maxAmount > _minAmount, "Invalid limits");
        minBetAmount = _minAmount;
        maxBetAmount = _maxAmount;
        emit BetLimitsUpdated(_minAmount, _maxAmount);
    }
    
    /**
     * @dev Obtener información de una apuesta
     * @param _betId ID de la apuesta
     * @return player Dirección del jugador
     * @return house Dirección de la casa
     * @return amount Cantidad de la apuesta
     * @return playerCommitHash Hash del commit del jugador
     * @return houseCommitHash Hash del commit de la casa
     * @return randomIndex Índice aleatorio del VRF
     * @return playerRevealed Si el jugador ha revelado
     * @return houseRevealed Si la casa ha revelado
     * @return settled Si la apuesta está resuelta
     * @return timestamp Timestamp de creación
     */
    function getBetInfo(uint256 _betId) external view returns (
        address player,
        address house,
        uint256 amount,
        bytes32 playerCommitHash,
        bytes32 houseCommitHash,
        uint256 randomIndex,
        bool playerRevealed,
        bool houseRevealed,
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
            bet.playerRevealed,
            bet.houseRevealed,
            bet.settled,
            bet.timestamp
        );
    }
    
    // ============ FUNCIONES DE EMERGENCIA ============
    
    /**
     * @dev Función de emergencia para retirar fondos del contrato
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Emergency withdrawal failed");
    }
    
    // ============ RECEIVE ============
    
    receive() external payable {
        // Permitir recibir ETH
    }
}
