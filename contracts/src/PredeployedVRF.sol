// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "./interfaces/IEnshrainedVRF.sol";

/// @title PredeployedVRF
/// @notice Enshrined VRF predeploy contract for OP Stack L2.
///         Provides synchronous, verifiable randomness to L2 contracts.
///
/// @dev    Deployed at 0x42000000000000000000000000000000000000F0.
///
///         The sequencer commits VRF results via system deposit transactions
///         by calling commitRandomness(). User contracts read randomness
///         via getRandomness(). Historical results can be queried via getResult().
///
///         Architecture:
///         - Sequencer computes ECVRF.Prove(sk, seed) off-chain in Go
///         - Sequencer injects deposit tx calling commitRandomness(nonce, beta, pi)
///         - User contracts call getRandomness() to consume committed randomness
///         - Anyone can verify proofs using the ECVRF verify precompile at 0x0101
contract PredeployedVRF is IEnshrainedVRF {
    /// @notice The DEPOSITOR_ACCOUNT address used by the OP Stack for system deposit txs.
    ///         Same as used by L1Block predeploy.
    address public constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    /// @notice The ECVRF verify precompile address in the OP Stack extended range.
    address public constant ECVRF_VERIFY_PRECOMPILE = address(0x0101);

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

    /// @notice Commits VRF randomness for consumption by user contracts.
    /// @dev    Only callable by DEPOSITOR_ACCOUNT via system deposit transaction.
    ///         The sequencer creates this deposit tx during block building after
    ///         computing ECVRF.Prove(sk, seed) in Go code.
    /// @param nonce The expected sequential nonce (must equal _commitNonce).
    /// @param beta  The VRF output hash (32 bytes).
    /// @param pi    The VRF proof (81 bytes).
    function commitRandomness(uint256 nonce, bytes32 beta, bytes calldata pi) external onlyDepositor {
        if (nonce != _commitNonce) revert NonceMismatch();
        if (pi.length != 81) revert InvalidProofLength();

        _results[nonce] = VrfResult({
            beta: beta,
            pi: pi,
            blockNumber: block.number
        });

        emit RandomnessCommitted(nonce, beta, msg.sender);

        unchecked {
            _commitNonce++;
        }
    }

    /// @notice Returns the next available random value.
    /// @dev    Each call consumes the next committed randomness in sequence.
    ///         Reverts if no committed randomness is available.
    /// @return randomness The VRF output (beta) cast to uint256.
    function getRandomness() external returns (uint256 randomness) {
        uint256 nonce = _consumeNonce;
        if (nonce >= _commitNonce) revert NoRandomnessAvailable();

        randomness = uint256(_results[nonce].beta);

        unchecked {
            _consumeNonce++;
        }
    }

    /// @notice Retrieves a historical VRF result by nonce.
    /// @param nonce The nonce of the desired result.
    /// @return beta The VRF output hash.
    /// @return pi   The VRF proof (81 bytes).
    function getResult(uint256 nonce) external view returns (bytes32 beta, bytes memory pi) {
        if (nonce >= _commitNonce) revert NonceNotCommitted();
        VrfResult storage result = _results[nonce];
        return (result.beta, result.pi);
    }

    /// @notice Returns the sequencer's VRF public key.
    /// @return pk Compressed SEC1 public key (33 bytes).
    function sequencerPublicKey() external view returns (bytes memory pk) {
        return _sequencerPublicKey;
    }

    /// @notice Returns the current commitment nonce.
    function commitNonce() external view returns (uint256) {
        return _commitNonce;
    }

    /// @notice Returns the current consumer nonce.
    function consumeNonce() external view returns (uint256) {
        return _consumeNonce;
    }

    /// @notice Updates the sequencer's VRF public key.
    /// @dev    Only callable by DEPOSITOR_ACCOUNT via system deposit transaction.
    ///         This is triggered when SystemConfig.setVRFPublicKey() is called on L1,
    ///         propagated through the derivation pipeline.
    /// @param pk The new compressed SEC1 public key (33 bytes).
    function setSequencerPublicKey(bytes calldata pk) external onlyDepositor {
        if (pk.length != 33) revert InvalidPublicKeyLength();
        _sequencerPublicKey = pk;
    }
}
