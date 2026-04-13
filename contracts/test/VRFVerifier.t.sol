// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VRFVerifier} from "../src/L1/VRFVerifier.sol";

contract VRFVerifierTest is Test {
    VRFVerifier public verifier;

    // Known test vector from Phase 1 ECVRF library
    // SK: c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721
    // Alpha: "sample"
    bytes constant KNOWN_PI =
        hex"0338ec99b5d0f94ebcc2c704c04af3de8b4289df8798e5fb9f920d7f5d77ac03d7"
        hex"718b9677d1c9348649ac2ec4f7ecbe512fdb380ec6ac688f38434354e8905edbc8"
        hex"defc09e0e649882ab1ae633119cb8f";

    bytes32 constant KNOWN_BETA = 0xd466c22e14dc3b7fd169668dd3ee9ac6351429a24aebc5e8af61a0f0de89b65a;

    function setUp() public {
        verifier = new VRFVerifier();
    }

    // ========== proofToHash ==========

    function test_proofToHash_knownVector() public view {
        bytes32 beta = verifier.proofToHash(KNOWN_PI);
        assertEq(beta, KNOWN_BETA);
    }

    function test_proofToHash_revertInvalidLength() public {
        vm.expectRevert(VRFVerifier.InvalidProofLength.selector);
        verifier.proofToHash(hex"0102");
    }

    function test_proofToHash_deterministic() public view {
        bytes32 beta1 = verifier.proofToHash(KNOWN_PI);
        bytes32 beta2 = verifier.proofToHash(KNOWN_PI);
        assertEq(beta1, beta2);
    }

    function test_proofToHash_differentProofDifferentBeta() public view {
        // Create a modified proof (different Gamma point)
        bytes memory modifiedPi = new bytes(81);
        for (uint256 i = 0; i < 81; i++) {
            modifiedPi[i] = KNOWN_PI[i];
        }
        modifiedPi[1] = bytes1(uint8(modifiedPi[1]) ^ 0xFF);

        bytes32 beta1 = verifier.proofToHash(KNOWN_PI);
        bytes32 beta2 = verifier.proofToHash(modifiedPi);
        assertTrue(beta1 != beta2);
    }

    // ========== computeSeed ==========

    function test_computeSeed() public view {
        uint256 blockNumber = 100;
        uint256 nonce = 0;

        bytes32 seed = verifier.computeSeed(blockNumber, nonce);
        bytes32 expected = sha256(abi.encodePacked(blockNumber, nonce));
        assertEq(seed, expected);
    }

    function test_computeSeed_differentInputsDifferentSeed() public view {
        bytes32 seed1 = verifier.computeSeed(100, 0);
        bytes32 seed2 = verifier.computeSeed(100, 1);
        bytes32 seed3 = verifier.computeSeed(101, 0);

        assertTrue(seed1 != seed2);
        assertTrue(seed1 != seed3);
        assertTrue(seed2 != seed3);
    }

    function testFuzz_computeSeed_deterministic(
        uint256 blockNumber,
        uint256 nonce
    ) public view {
        bytes32 seed1 = verifier.computeSeed(blockNumber, nonce);
        bytes32 seed2 = verifier.computeSeed(blockNumber, nonce);
        assertEq(seed1, seed2);
    }

    // ========== verifySeed ==========

    function test_verifySeed_valid() public view {
        uint256 blockNumber = 100;
        uint256 nonce = 0;

        bytes32 seed = sha256(abi.encodePacked(blockNumber, nonce));
        assertTrue(verifier.verifySeed(blockNumber, nonce, seed));
    }

    function test_verifySeed_invalid() public view {
        uint256 blockNumber = 100;
        uint256 nonce = 0;

        bytes32 wrongSeed = keccak256("wrong");
        assertFalse(verifier.verifySeed(blockNumber, nonce, wrongSeed));
    }

    function test_verifySeed_wrongNonce() public view {
        uint256 blockNumber = 100;

        bytes32 seed = sha256(abi.encodePacked(blockNumber, uint256(0)));
        // Verify with wrong nonce
        assertFalse(verifier.verifySeed(blockNumber, 1, seed));
    }

    // ========== verifyNonceSequence ==========

    function test_verifyNonceSequence_valid() public view {
        assertTrue(verifier.verifyNonceSequence(0, 1));
        assertTrue(verifier.verifyNonceSequence(42, 43));
        assertTrue(verifier.verifyNonceSequence(999, 1000));
    }

    function test_verifyNonceSequence_invalid() public view {
        assertFalse(verifier.verifyNonceSequence(0, 0));  // same
        assertFalse(verifier.verifyNonceSequence(0, 2));  // skip
        assertFalse(verifier.verifyNonceSequence(5, 3));  // backward
    }

    // ========== verifyProofStructure ==========

    function test_verifyProofStructure_betaMatchesProof() public view {
        bytes memory pk = hex"02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524";

        // Use known proof and beta
        bool valid = verifier.verifyProofStructure(pk, bytes32(0), KNOWN_BETA, KNOWN_PI);
        assertTrue(valid);
    }

    function test_verifyProofStructure_betaMismatch() public view {
        bytes memory pk = hex"02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524";

        bytes32 wrongBeta = keccak256("wrong");
        bool valid = verifier.verifyProofStructure(pk, bytes32(0), wrongBeta, KNOWN_PI);
        assertFalse(valid);
    }

    function test_verifyProofStructure_invalidPKLength() public view {
        bool valid = verifier.verifyProofStructure(hex"0102", bytes32(0), KNOWN_BETA, KNOWN_PI);
        assertFalse(valid);
    }

    function test_verifyProofStructure_invalidProofLength() public view {
        bytes memory pk = hex"02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524";

        bool valid = verifier.verifyProofStructure(pk, bytes32(0), KNOWN_BETA, hex"0102");
        assertFalse(valid);
    }

    function test_verifyProofStructure_invalidS() public view {
        bytes memory pk = hex"02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524";

        // Create proof with s >= N (curve order)
        bytes memory badPi = new bytes(81);
        for (uint256 i = 0; i < 33; i++) {
            badPi[i] = KNOWN_PI[i];
        }
        for (uint256 i = 33; i < 49; i++) {
            badPi[i] = KNOWN_PI[i];
        }
        // Set s = 0xFFFF...FFFF (> N)
        for (uint256 i = 49; i < 81; i++) {
            badPi[i] = bytes1(0xFF);
        }

        bool valid = verifier.verifyProofStructure(pk, bytes32(0), bytes32(0), badPi);
        assertFalse(valid);
    }

    // ========== Gas Measurement ==========

    function test_gas_proofToHash() public {
        uint256 gasBefore = gasleft();
        verifier.proofToHash(KNOWN_PI);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("proofToHash gas", gasUsed);
    }

    function test_gas_computeSeed() public {
        uint256 gasBefore = gasleft();
        verifier.computeSeed(100, 0);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("computeSeed gas", gasUsed);
    }

    function test_gas_verifyProofStructure() public {
        bytes memory pk = hex"02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524";
        uint256 gasBefore = gasleft();
        verifier.verifyProofStructure(pk, bytes32(0), KNOWN_BETA, KNOWN_PI);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("verifyProofStructure gas", gasUsed);
    }
}
