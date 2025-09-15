// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "./FlipCoinDualZKVerifier.sol";

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
    
    // Verificador ZK de doble condición
    FlipCoinDualZKVerifier public immutable dualZKVerifier;
    
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
        address _dualZKVerifier
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        houseFee = _houseFee;
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;
        dualZKVerifier = FlipCoinDualZKVerifier(_dualZKVerifier);
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
     * @dev La casa se compromete con su preimagen
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
        
        // Solicitar VRF para índice aleatorio
        _requestVRF(_betId);
    }
    
    /**
     * @dev Resolver apuesta con doble condición ZK
     * @param _betId ID de la apuesta
     * @param _playerPreimage Preimagen del jugador (512 bits = 16 uint32)
     * @param _housePreimage Preimagen de la casa (512 bits = 16 uint32)
     * @param _expectedResult Resultado esperado del XOR (0 o 1)
     * @param _zkProof Prueba ZK de doble condición
     */
    function settleBetWithDualZK(
        uint256 _betId,
        uint32[16] calldata _playerPreimage,
        uint32[16] calldata _housePreimage,
        uint8 _expectedResult,
        bytes calldata _zkProof
    ) external nonReentrant {
        Bet storage bet = bets[_betId];
        require(bet.player == msg.sender || bet.house == msg.sender, "Only player or house can settle");
        require(!bet.settled, "Bet already settled");
        require(bet.randomIndex > 0, "VRF not fulfilled yet");
        require(_expectedResult <= 1, "Invalid expected result");
        
        // Verificar prueba ZK de doble condición
        require(
            dualZKVerifier.verifyDualProof(
                _playerPreimage,
                bet.playerCommit,
                _housePreimage,
                bet.houseCommit,
                bet.randomIndex,
                _expectedResult,
                _zkProof
            ),
            "Invalid dual ZK proof"
        );
        
        bet.settled = true;
        
        // Calcular bits y resultado
        uint8 playerBit = _getBitAt(_playerPreimage, bet.randomIndex);
        uint8 houseBit = _getBitAt(_housePreimage, bet.randomIndex);
        uint8 result = playerBit ^ houseBit;
        
        // Verificar que el resultado coincide con el esperado
        require(result == _expectedResult, "Result mismatch");
        
        // Determinar ganador y distribuir fondos
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
        
        emit BetSettled(_betId, winner, payout, playerBit, houseBit, result);
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
    
    // ============ FUNCIONES AUXILIARES ============
    
    /**
     * @dev Obtener bit en posición específica de preimagen de 512 bits
     * @param _preimage Preimagen como array de 16 uint32
     * @param _position Posición del bit (0-511)
     * @return Bit en la posición especificada
     */
    function _getBitAt(uint32[16] calldata _preimage, uint256 _position) internal pure returns (uint8) {
        require(_position < 512, "Position out of range");
        uint256 uint32Index = _position / 32;
        uint256 bitIndex = _position % 32;
        return uint8(_preimage[uint32Index] >> bitIndex) & 1;
    }
    
    /**
     * @dev Obtener información de una apuesta
     * @param _betId ID de la apuesta
     * @return player Dirección del jugador
     * @return house Dirección de la casa
     * @return amount Cantidad de la apuesta
     * @return playerCommit Commitment del jugador
     * @return houseCommit Commitment de la casa
     * @return randomIndex Índice aleatorio del VRF
     * @return settled Si la apuesta está resuelta
     * @return timestamp Timestamp de creación
     */
    function getBetInfo(uint256 _betId) external view returns (
        address player,
        address house,
        uint256 amount,
        bytes32 playerCommit,
        bytes32 houseCommit,
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
