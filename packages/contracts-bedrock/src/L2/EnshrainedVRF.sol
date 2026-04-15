// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IEnshrainedVRF } from "interfaces/L2/IEnshrainedVRF.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:predeploy 0x42000000000000000000000000000000000000f0
/// @title EnshrainedVRF
/// @notice Enshrined VRF predeploy contract for OP Stack L2.
///         Provides synchronous, verifiable randomness to L2 contracts.
///
///         The sequencer commits one VRF result per block via a system deposit
///         transaction. User contracts call getRandomness() to receive per-call
///         unique values derived from the committed beta:
///           randomness = keccak256(beta, callCounter)
contract EnshrainedVRF is IEnshrainedVRF, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.1.0
    string public constant version = "1.1.0";

    /// @notice The DEPOSITOR_ACCOUNT address used by the OP Stack for system deposit txs.
    address public constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    /// @notice A VRF result containing the seed, output hash, and proof.
    struct VrfResult {
        bytes32 seed;
        bytes32 beta;
        bytes pi;
        uint256 blockNumber;
    }

    /// @notice The sequencer's compressed SEC1 public key (33 bytes).
    bytes private _sequencerPublicKey;

    /// @notice The next nonce to be used for commitment (monotonically increasing, one per block).
    uint256 private _commitNonce;

    /// @notice The beta committed for the current block.
    bytes32 private _currentBeta;

    /// @notice The block number of the current commitment.
    uint256 private _currentBlock;

    /// @notice Counter for per-call derivation within the current block.
    uint256 private _callCounter;

    /// @notice Mapping from nonce to VRF result (historical record).
    mapping(uint256 => VrfResult) private _results;

    /// @notice Thrown when a non-depositor account calls a system-only function.
    error OnlyDepositor();

    /// @notice Thrown when no committed randomness is available for the current block.
    error NoRandomnessAvailable();

    /// @notice Thrown when querying a nonce that hasn't been committed yet.
    error NonceNotCommitted();

    /// @notice Thrown when the committed nonce doesn't match the expected value.
    error NonceMismatch();

    /// @notice Thrown when the public key has invalid length.
    error InvalidPublicKeyLength();

    /// @notice Thrown when the proof has invalid length.
    error InvalidProofLength();

    /// @notice Restricts function to the DEPOSITOR_ACCOUNT.
    modifier onlyDepositor() {
        _checkDepositor();
        _;
    }

    function _checkDepositor() internal view {
        if (msg.sender != DEPOSITOR_ACCOUNT) revert OnlyDepositor();
    }

    /// @inheritdoc IEnshrainedVRF
    function commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes calldata pi) external onlyDepositor {
        // nonce parameter is informational (used for seed construction and fault proofs).
        // Contract uses its own monotonic _commitNonce to avoid sync issues with the sequencer.
        if (pi.length != 81) revert InvalidProofLength();

        _results[_commitNonce] = VrfResult({
            seed: seed,
            beta: beta,
            pi: pi,
            blockNumber: block.number
        });

        _currentBeta = beta;
        _currentBlock = block.number;
        _callCounter = 0;

        emit RandomnessCommitted(nonce, beta, msg.sender);

        unchecked {
            _commitNonce++;
        }
    }

    /// @inheritdoc IEnshrainedVRF
    function getRandomness() external returns (uint256 randomness) {
        if (_currentBlock != block.number) revert NoRandomnessAvailable();

        randomness = uint256(keccak256(abi.encodePacked(_currentBeta, _callCounter)));

        unchecked {
            _callCounter++;
        }
    }

    /// @inheritdoc IEnshrainedVRF
    function getResult(uint256 nonce) external view returns (bytes32 seed, bytes32 beta, bytes memory pi) {
        if (nonce >= _commitNonce) revert NonceNotCommitted();
        VrfResult storage result = _results[nonce];
        return (result.seed, result.beta, result.pi);
    }

    /// @inheritdoc IEnshrainedVRF
    function sequencerPublicKey() external view returns (bytes memory pk) {
        return _sequencerPublicKey;
    }

    /// @inheritdoc IEnshrainedVRF
    function commitNonce() external view returns (uint256) {
        return _commitNonce;
    }

    /// @inheritdoc IEnshrainedVRF
    function callCounter() external view returns (uint256) {
        return _callCounter;
    }

    /// @notice Updates the sequencer's VRF public key.
    /// @dev    Only callable by DEPOSITOR_ACCOUNT via system deposit transaction.
    /// @param pk The new compressed SEC1 public key (33 bytes).
    function setSequencerPublicKey(bytes calldata pk) external onlyDepositor {
        if (pk.length != 33) revert InvalidPublicKeyLength();
        _sequencerPublicKey = pk;
        emit SequencerPublicKeyUpdated(pk);
    }
}
