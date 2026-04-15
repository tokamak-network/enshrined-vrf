// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IEnshrainedVRF
/// @notice Interface for the Enshrined VRF predeploy contract.
///         One VRF commitment per block; getRandomness() derives per-call
///         unique values via keccak256(beta, callCounter).
interface IEnshrainedVRF {
    event RandomnessCommitted(uint256 indexed nonce, bytes32 beta, address indexed caller);
    event SequencerPublicKeyUpdated(bytes pk);

    function getRandomness() external returns (uint256 randomness);
    function getResult(uint256 nonce) external view returns (bytes32 seed, bytes32 beta, bytes memory pi);
    function sequencerPublicKey() external view returns (bytes memory pk);
    function commitNonce() external view returns (uint256);
    function callCounter() external view returns (uint256);
    function commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes calldata pi) external;
    function setSequencerPublicKey(bytes calldata pk) external;
}
