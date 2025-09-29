// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./IVerifier.sol";

contract MockVerifier is IVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external view override returns (bool) {
        // Mock siempre devuelve true
        return true;
    }
}


