// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title ArcadeVRF
/// @notice Demo-only drop-in replacement for the EnshrainedVRF predeploy.
///         Preserves the IEnshrainedVRF ABI and on-chain verifiability of
///         committed betas, but relaxes the "commit must be in the same
///         block as the consumer tx" rule so that getRandomness() succeeds
///         from any user tx — essential for the local arcade demo where the
///         sequencer can't guarantee tx-0 placement on Anvil.
///
///         Each getRandomness() call derives a unique value from the latest
///         committed beta plus a monotonically-increasing call counter, so
///         multiple calls (in one tx or across blocks) never collide.
///
///         NOT FOR PRODUCTION. The real EnshrainedVRF binds randomness to
///         the block's beta, preventing the sequencer from deferring a
///         commit until it sees user txs.
contract ArcadeVRF is IEnshrainedVRF {
    string public constant version = "arcade-1.0.0";

    address public constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    struct VrfResult {
        bytes32 seed;
        bytes32 beta;
        bytes pi;
        uint256 blockNumber;
    }

    bytes   private _sequencerPublicKey;
    uint256 private _commitNonce;
    bytes32 private _latestBeta;
    uint256 private _callCounter;
    mapping(uint256 => VrfResult) private _results;

    error OnlyDepositor();
    error NoCommitYet();
    error NonceNotCommitted();
    error InvalidPublicKeyLength();
    error InvalidProofLength();

    modifier onlyDepositor() {
        if (msg.sender != DEPOSITOR_ACCOUNT) revert OnlyDepositor();
        _;
    }

    function commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes calldata pi)
        external
        onlyDepositor
    {
        if (pi.length != 81) revert InvalidProofLength();
        _results[_commitNonce] = VrfResult({
            seed: seed, beta: beta, pi: pi, blockNumber: block.number
        });
        _latestBeta = beta;
        emit RandomnessCommitted(nonce, beta, msg.sender);
        unchecked { _commitNonce++; }
    }

    function getRandomness() external returns (uint256 randomness) {
        if (_latestBeta == bytes32(0)) revert NoCommitYet();
        // Mix the call counter AND the current block into the derivation —
        // ensures calls across blocks can't reuse a prior result even if no
        // new commit has arrived yet (e.g., between sequencer ticks).
        randomness = uint256(keccak256(abi.encodePacked(_latestBeta, _callCounter, block.number)));
        unchecked { _callCounter++; }
    }

    function getResult(uint256 nonce) external view returns (bytes32 seed, bytes32 beta, bytes memory pi) {
        if (nonce >= _commitNonce) revert NonceNotCommitted();
        VrfResult storage r = _results[nonce];
        return (r.seed, r.beta, r.pi);
    }

    function sequencerPublicKey() external view returns (bytes memory) { return _sequencerPublicKey; }
    function commitNonce()        external view returns (uint256)      { return _commitNonce; }
    function callCounter()        external view returns (uint256)      { return _callCounter; }

    function setSequencerPublicKey(bytes calldata pk) external onlyDepositor {
        if (pk.length != 33) revert InvalidPublicKeyLength();
        _sequencerPublicKey = pk;
        emit SequencerPublicKeyUpdated(pk);
    }
}
