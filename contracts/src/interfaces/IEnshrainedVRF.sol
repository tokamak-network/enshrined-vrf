// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IEnshrainedVRF
/// @notice Interface for the Enshrined VRF predeploy contract.
///         Provides synchronous, verifiable randomness to L2 contracts.
interface IEnshrainedVRF {
    /// @notice Emitted when new randomness is committed by the sequencer via deposit tx.
    /// @param nonce     The sequential nonce for this VRF result.
    /// @param beta      The VRF output hash (randomness).
    /// @param caller    The address that triggered the commitment (DEPOSITOR_ACCOUNT).
    event RandomnessCommitted(uint256 indexed nonce, bytes32 beta, address indexed caller);

    /// @notice Returns the next available random value for the current block.
    /// @dev    Reads from randomness committed by the sequencer's deposit transaction.
    ///         Each call increments an internal consumer nonce and returns a different value
    ///         derived from the committed randomness pool.
    /// @return randomness The VRF output (beta) as uint256.
    function getRandomness() external returns (uint256 randomness);

    /// @notice Retrieves a historical VRF result by nonce.
    /// @param nonce The nonce of the desired result.
    /// @return beta The VRF output hash.
    /// @return pi   The VRF proof (81 bytes).
    function getResult(uint256 nonce) external view returns (bytes32 beta, bytes memory pi);

    /// @notice Returns the sequencer's VRF public key.
    /// @return pk Compressed SEC1 public key (33 bytes).
    function sequencerPublicKey() external view returns (bytes memory pk);

    /// @notice Returns the current commitment nonce (total commitments made).
    function commitNonce() external view returns (uint256);
}
