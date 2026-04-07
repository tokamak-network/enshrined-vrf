// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IEnshrainedVRF } from "interfaces/L2/IEnshrainedVRF.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:predeploy 0x42000000000000000000000000000000000000f0
/// @title EnshrainedVRF
/// @notice Enshrined VRF predeploy contract for OP Stack L2.
///         Provides synchronous, verifiable randomness to L2 contracts.
///         The sequencer commits VRF results via system deposit transactions
///         by calling commitRandomness(). User contracts read randomness
///         via getRandomness().
contract EnshrainedVRF is IEnshrainedVRF, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The DEPOSITOR_ACCOUNT address used by the OP Stack for system deposit txs.
    address public constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    /// @notice A VRF result containing the output hash and proof.
    struct VrfResult {
        bytes32 beta;
        bytes pi;
        uint256 blockNumber;
    }

    /// @notice The sequencer's compressed SEC1 public key (33 bytes).
    bytes private _sequencerPublicKey;

    /// @notice The next nonce to be used for commitment (monotonically increasing).
    uint256 private _commitNonce;

    /// @notice The next nonce to be consumed by getRandomness().
    uint256 private _consumeNonce;

    /// @notice Mapping from nonce to VRF result.
    mapping(uint256 => VrfResult) private _results;

    /// @notice Thrown when a non-depositor account calls a system-only function.
    error OnlyDepositor();

    /// @notice Thrown when no committed randomness is available for consumption.
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
    function getRandomness() external returns (uint256 randomness) {
        uint256 nonce = _consumeNonce;
        if (nonce >= _commitNonce) revert NoRandomnessAvailable();
        randomness = uint256(_results[nonce].beta);
        unchecked {
            _consumeNonce++;
        }
    }

    /// @inheritdoc IEnshrainedVRF
    function getResult(uint256 nonce) external view returns (bytes32 beta, bytes memory pi) {
        if (nonce >= _commitNonce) revert NonceNotCommitted();
        VrfResult storage result = _results[nonce];
        return (result.beta, result.pi);
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
    function consumeNonce() external view returns (uint256) {
        return _consumeNonce;
    }

    /// @notice Commits VRF randomness for consumption by user contracts.
    /// @dev    Only callable by DEPOSITOR_ACCOUNT via system deposit transaction.
    /// @param nonce The expected sequential nonce (must equal _commitNonce).
    /// @param beta  The VRF output hash (32 bytes).
    /// @param pi    The VRF proof (81 bytes).
    function commitRandomness(uint256 nonce, bytes32 beta, bytes calldata pi) external onlyDepositor {
        if (nonce != _commitNonce) revert NonceMismatch();
        if (pi.length != 81) revert InvalidProofLength();
        _results[nonce] = VrfResult({ beta: beta, pi: pi, blockNumber: block.number });
        emit RandomnessCommitted(nonce, beta, msg.sender);
        unchecked {
            _commitNonce++;
        }
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
