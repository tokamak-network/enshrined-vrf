// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @notice Deterministic stand-in for EnshrainedVRF during unit tests.
///         Each call increments a counter and hashes it to produce randomness.
contract MockVRF is IEnshrainedVRF {
    uint256 public override callCounter;
    uint256 public override commitNonce;
    bytes private _pk;

    function getRandomness() external override returns (uint256 randomness) {
        callCounter += 1;
        randomness = uint256(keccak256(abi.encode(callCounter)));
    }

    function getResult(uint256) external pure override returns (bytes32, bytes32, bytes memory) {
        return (bytes32(0), bytes32(0), bytes(""));
    }

    function sequencerPublicKey() external view override returns (bytes memory) {
        return _pk;
    }

    function commitRandomness(uint256, bytes32, bytes32, bytes calldata) external override {}

    function setSequencerPublicKey(bytes calldata pk) external override {
        _pk = pk;
    }
}
