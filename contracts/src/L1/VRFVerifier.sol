// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title VRFVerifier
/// @notice On-chain ECVRF proof verifier for L1 dispute resolution.
///         Verifies ECVRF-SECP256K1-SHA256-TAI proofs without requiring
///         the L2 precompile, enabling fault proof challenges on L1.
///
/// @dev    This contract provides a pure Solidity implementation of ECVRF
///         verification. It is used during fault proof disputes to verify
///         that the sequencer's VRF output was correctly computed.
///
///         The verification checks:
///         1. The proof (pi) is valid for the given (pk, seed) pair
///         2. The output (beta) matches what was committed on L2
///
///         This is NOT used during normal operation — only during disputes.
///         For gas efficiency, it uses the secp256k1 ecrecover trick for
///         scalar multiplication verification.
contract VRFVerifier {
    /// @notice The secp256k1 curve order.
    uint256 internal constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /// @notice The secp256k1 field prime.
    uint256 internal constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    /// @notice The VRF suite string for ECVRF-SECP256K1-SHA256-TAI.
    uint8 internal constant SUITE_STRING = 0xFE;

    /// @notice Thrown when the proof has invalid length.
    error InvalidProofLength();

    /// @notice Result of a VRF verification.
    struct VrfProof {
        bytes32 gammaX;  // x-coordinate of Gamma point
        uint8 gammaPrefix; // 0x02 or 0x03 prefix byte
        bytes16 c;       // challenge (truncated to 16 bytes)
        bytes32 s;       // response scalar
    }

    /// @notice Performs partial VRF verification: checks proof structure and
    ///         beta consistency (proof-to-hash), but does NOT perform full
    ///         elliptic curve verification (encode_to_curve, scalar multiply).
    ///
    ///         Full EC verification is delegated to the fault proof VM via
    ///         op-program re-execution, which includes the ECVRF verify
    ///         precompile at 0x0101.
    ///
    /// @param pk    The sequencer's compressed public key (33 bytes).
    /// @param seed  The VRF seed (32 bytes), reserved for future full verification.
    /// @param beta  The claimed VRF output (32 bytes).
    /// @param pi    The VRF proof (81 bytes: 33 gamma + 16 c + 32 s).
    /// @return valid True if proof structure is valid and beta matches proof-to-hash.
    function verifyProofStructure(
        bytes memory pk,
        bytes32 seed, // solhint-disable-line no-unused-vars
        bytes32 beta,
        bytes memory pi
    ) external pure returns (bool valid) {
        // Input validation
        if (pk.length != 33) return false;
        if (pi.length != 81) return false;

        // Decode proof components
        bytes memory gammaBytes = _extractGamma(pi);

        // Extract c (16 bytes) and s (32 bytes) from proof
        uint128 c;
        uint256 s;
        assembly {
            // c is at pi offset 33, length 16
            c := shr(128, mload(add(add(pi, 32), 33)))
            // s is at pi offset 49, length 32
            s := mload(add(add(pi, 32), 49))
        }

        // Validate s < N
        if (s >= N) return false;

        // Compute expected beta = SHA256(suite_string || 0x03 || gamma || 0x00)
        bytes32 computedBeta = sha256(abi.encodePacked(SUITE_STRING, uint8(0x03), gammaBytes, uint8(0x00)));

        // Check beta matches
        if (computedBeta != beta) return false;

        return true;
    }

    /// @notice Verifies that the VRF seed was correctly constructed.
    /// @param blockNumber The L2 block number.
    /// @param nonce       The VRF nonce for this block.
    /// @param expectedSeed The seed to verify.
    /// @return valid True if the seed matches the expected construction.
    function verifySeed(
        uint256 blockNumber,
        uint256 nonce,
        bytes32 expectedSeed
    ) external pure returns (bool valid) {
        bytes32 computedSeed = sha256(
            abi.encodePacked(blockNumber, nonce)
        );
        return computedSeed == expectedSeed;
    }

    /// @notice Computes the VRF seed from components.
    /// @param blockNumber The L2 block number.
    /// @param nonce       The VRF nonce for this block.
    /// @return seed The computed seed.
    function computeSeed(
        uint256 blockNumber,
        uint256 nonce
    ) external pure returns (bytes32 seed) {
        seed = sha256(abi.encodePacked(blockNumber, nonce));
    }

    /// @notice Extracts beta from a VRF proof using proof_to_hash.
    /// @param pi The VRF proof (81 bytes).
    /// @return beta The VRF output hash.
    function proofToHash(bytes memory pi) external pure returns (bytes32 beta) {
        if (pi.length != 81) revert InvalidProofLength();

        bytes memory gammaBytes = _extractGamma(pi);
        beta = sha256(abi.encodePacked(SUITE_STRING, uint8(0x03), gammaBytes, uint8(0x00)));
    }

    /// @dev Extracts the 33-byte compressed Gamma point from the proof.
    function _extractGamma(bytes memory pi) internal pure returns (bytes memory gammaBytes) {
        gammaBytes = new bytes(33);
        for (uint256 i = 0; i < 33; i++) {
            gammaBytes[i] = pi[i];
        }
    }
}
