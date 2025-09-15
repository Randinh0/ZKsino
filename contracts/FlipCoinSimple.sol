// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FlipCoinSimple {
    struct Bet { address player; uint256 amount; uint256 nonce; bool resolved; bool won; }
    mapping(uint256 => Bet) public bets;
    uint256 public nextBetId;
    address public owner;
    uint16 public houseFeeBP = 200; // 2%

    event BetPlaced(uint256 indexed id, address indexed player, uint256 amount);
    event BetResolved(uint256 indexed id, address indexed player, bool won);

    constructor(){ owner = msg.sender; }

    function placeBet(uint256 clientNonce) external payable returns (uint256 id) {
        require(msg.value > 0, "stake>0");
        id = nextBetId++;
        bets[id] = Bet({ player: msg.sender, amount: msg.value, nonce: clientNonce, resolved: false, won: false });
        emit BetPlaced(id, msg.sender, msg.value);
        // Optionally auto-resolve (see security note)
        _resolve(id);
    }

    function _resolve(uint256 id) internal {
        Bet storage b = bets[id];
        require(!b.resolved, "already resolved");
        // WARNING: insecure source of randomness
        uint256 r = uint256(keccak256(abi.encodePacked(blockhash(block.number-1), b.player, b.nonce)));
        bool win = (r % 2) == 1;
        b.resolved = true;
        b.won = win;
        if (win) {
            uint256 payout = (b.amount * 2 * (10000 - houseFeeBP)) / 10000;
            // best-effort send
            (bool ok, ) = b.player.call{value: payout}("");
            if (!ok) { /* handle failed payout: mark withdrawable, etc. */ }
        }
        emit BetResolved(id, b.player, win);
    }

    // owner withdraw
    function withdraw() external {
        require(msg.sender == owner, "only owner");
        payable(owner).transfer(address(this).balance);
    }

    receive() external payable {}
}
