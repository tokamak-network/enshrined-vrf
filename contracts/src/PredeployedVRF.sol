// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "./interfaces/IEnshrainedVRF.sol";

/// @title PredeployedVRF
/// @notice Enshrined VRF predeploy contract for OP Stack L2.
///         Provides synchronous, verifiable randomness to L2 contracts.
///
/// @dev    Deployed at 0x42000000000000000000000000000000000000F0.
///
///         The sequencer commits one VRF result per block via a system deposit
///         transaction. User contracts call getRandomness() to receive per-call
///         unique values derived from the committed beta:
///           randomness = keccak256(beta, callCounter)
///         This allows unlimited getRandomness() calls per block from a single
///         VRF commitment, avoiding the chicken-and-egg problem of needing to
///         know the call count before building the block.
///
///         Architecture:
///         - Sequencer computes ECVRF.Prove(sk, seed) off-chain in TEE
///         - Sequencer injects one deposit tx per block: commitRandomness(nonce, beta, pi)
///         - User contracts call getRandomness() — each call returns a unique derived value
///         - Anyone can verify proofs using the ECVRF verify precompile at 0x0101
contract PredeployedVRF is IEnshrainedVRF {
    /// @notice The DEPOSITOR_ACCOUNT address used by the OP Stack for system deposit txs.
    ///         Same as used by L1Block predeploy.
    address public constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    /// @notice The ECVRF verify precompile address in the OP Stack extended range.
    address public constant ECVRF_VERIFY_PRECOMPILE = address(0x0101);

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

    /// @notice Commits VRF randomness for the current block.
    /// @dev    Only callable by DEPOSITOR_ACCOUNT via system deposit transaction.
    ///         The sequencer creates one deposit tx per block during block building
    ///         after computing ECVRF.Prove(sk, seed) in the TEE enclave.
    /// @param nonce Informational nonce (used for seed construction and fault proofs).
    /// @param seed  The VRF seed used for proof generation (32 bytes).
    /// @param beta  The VRF output hash (32 bytes).
    /// @param pi    The VRF proof (81 bytes).
    function commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes calldata pi) external onlyDepositor {
        // nonce parameter is informational — contract uses internal _commitNonce
        // to avoid sync issues between sequencer and contract state.
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

    /// @notice Returns a unique random value for each call within the current block.
    /// @dev    Derives per-call randomness from the block's committed beta:
    ///           randomness = keccak256(beta, callCounter++)
    ///         Reverts if no randomness has been committed for the current block.
    /// @return randomness A unique derived value per call.
    function getRandomness() external returns (uint256 randomness) {
        if (_currentBlock != block.number) revert NoRandomnessAvailable();

        randomness = uint256(keccak256(abi.encodePacked(_currentBeta, _callCounter)));

        unchecked {
            _callCounter++;
        }
    }

    /// @notice Retrieves a historical VRF result by nonce.
    /// @param nonce The nonce of the desired result.
    /// @return seed The VRF seed used for proof generation.
    /// @return beta The VRF output hash.
    /// @return pi   The VRF proof (81 bytes).
    function getResult(uint256 nonce) external view returns (bytes32 seed, bytes32 beta, bytes memory pi) {
        if (nonce >= _commitNonce) revert NonceNotCommitted();
        VrfResult storage result = _results[nonce];
        return (result.seed, result.beta, result.pi);
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

    /// @notice Returns the per-call counter for the current block.
    function callCounter() external view returns (uint256) {
        return _callCounter;
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
