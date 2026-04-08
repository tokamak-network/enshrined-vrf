// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PredeployedVRF} from "../src/PredeployedVRF.sol";
import {IEnshrainedVRF} from "../src/interfaces/IEnshrainedVRF.sol";

contract PredeployedVRFTest is Test {
    PredeployedVRF public vrf;

    address constant DEPOSITOR = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;
    address constant PREDEPLOY_ADDR = 0x42000000000000000000000000000000000000f0;
    address constant USER = address(0xBEEF);

    // Sample VRF data
    bytes32 constant SEED_0 = keccak256("seed0");
    bytes32 constant SEED_1 = keccak256("seed1");
    bytes32 constant SEED_2 = keccak256("seed2");
    bytes32 constant BETA_0 = keccak256("beta0");
    bytes32 constant BETA_1 = keccak256("beta1");
    bytes32 constant BETA_2 = keccak256("beta2");

    bytes constant SAMPLE_PK =
        hex"0338ec99b5d0f94ebcc2c704c04af3de8b4289df8798e5fb9f920d7f5d77ac03d7";

    function _samplePi() internal pure returns (bytes memory) {
        // 81 bytes of sample proof data
        return
            hex"0338ec99b5d0f94ebcc2c704c04af3de8b4289df8798e5fb9f920d7f5d77ac03d7"
            hex"718b9677d1c9348649ac2ec4f7ecbe512fdb380ec6ac688f38434354e8905edbc8"
            hex"defc09e0e649882ab1ae633119cb8f";
    }

    function setUp() public {
        // Deploy at the predeploy address
        vrf = new PredeployedVRF();
        vm.etch(PREDEPLOY_ADDR, address(vrf).code);
        vrf = PredeployedVRF(PREDEPLOY_ADDR);
    }

    // ========== CONSTANTS ==========

    function test_depositorAccountAddress() public view {
        assertEq(vrf.DEPOSITOR_ACCOUNT(), DEPOSITOR);
    }

    function test_ecvrfVerifyPrecompileAddress() public view {
        assertEq(vrf.ECVRF_VERIFY_PRECOMPILE(), address(0x0101));
    }

    // ========== setSequencerPublicKey ==========

    function test_setSequencerPublicKey_success() public {
        vm.prank(DEPOSITOR);
        vrf.setSequencerPublicKey(SAMPLE_PK);

        bytes memory stored = vrf.sequencerPublicKey();
        assertEq(stored.length, 33);
        assertEq(keccak256(stored), keccak256(SAMPLE_PK));
    }

    function test_setSequencerPublicKey_revertNotDepositor() public {
        vm.prank(USER);
        vm.expectRevert(PredeployedVRF.OnlyDepositor.selector);
        vrf.setSequencerPublicKey(SAMPLE_PK);
    }

    function test_setSequencerPublicKey_revertInvalidLength() public {
        vm.prank(DEPOSITOR);
        vm.expectRevert(PredeployedVRF.InvalidPublicKeyLength.selector);
        vrf.setSequencerPublicKey(hex"0102"); // 2 bytes, not 33
    }

    function test_setSequencerPublicKey_revertInvalidLength65() public {
        vm.prank(DEPOSITOR);
        bytes memory uncompressed = new bytes(65);
        vm.expectRevert(PredeployedVRF.InvalidPublicKeyLength.selector);
        vrf.setSequencerPublicKey(uncompressed);
    }

    function test_setSequencerPublicKey_overwrite() public {
        bytes memory pk1 = SAMPLE_PK;
        bytes memory pk2 = hex"0238ec99b5d0f94ebcc2c704c04af3de8b4289df8798e5fb9f920d7f5d77ac03d7";

        vm.prank(DEPOSITOR);
        vrf.setSequencerPublicKey(pk1);

        vm.prank(DEPOSITOR);
        vrf.setSequencerPublicKey(pk2);

        assertEq(keccak256(vrf.sequencerPublicKey()), keccak256(pk2));
    }

    // ========== commitRandomness ==========

    function test_commitRandomness_success() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        assertEq(vrf.commitNonce(), 1);
    }

    function test_commitRandomness_emitsEvent() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        vm.expectEmit(true, true, true, true);
        emit IEnshrainedVRF.RandomnessCommitted(0, BETA_0, DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);
    }

    function test_commitRandomness_revertNotDepositor() public {
        vm.prank(USER);
        vm.expectRevert(PredeployedVRF.OnlyDepositor.selector);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());
    }

    function test_commitRandomness_revertNonceMismatch() public {
        vm.prank(DEPOSITOR);
        vm.expectRevert(PredeployedVRF.NonceMismatch.selector);
        vrf.commitRandomness(1, SEED_0, BETA_0, _samplePi()); // expected 0
    }

    function test_commitRandomness_revertInvalidProofLength() public {
        vm.prank(DEPOSITOR);
        vm.expectRevert(PredeployedVRF.InvalidProofLength.selector);
        vrf.commitRandomness(0, SEED_0, BETA_0, hex"0102"); // 2 bytes, not 81
    }

    function test_commitRandomness_sequential() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(1, SEED_1, BETA_1, pi);

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(2, SEED_2, BETA_2, pi);

        assertEq(vrf.commitNonce(), 3);
    }

    function test_commitRandomness_skipNonceReverts() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        // Try to skip nonce 1
        vm.prank(DEPOSITOR);
        vm.expectRevert(PredeployedVRF.NonceMismatch.selector);
        vrf.commitRandomness(2, SEED_2, BETA_2, pi);
    }

    // ========== getRandomness ==========

    function test_getRandomness_success() public {
        // Commit one value
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Consume it
        vm.prank(USER);
        uint256 randomness = vrf.getRandomness();
        assertEq(randomness, uint256(BETA_0));
    }

    function test_getRandomness_sequential() public {
        bytes memory pi = _samplePi();

        // Commit 3 values
        vm.startPrank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);
        vrf.commitRandomness(1, SEED_1, BETA_1, pi);
        vrf.commitRandomness(2, SEED_2, BETA_2, pi);
        vm.stopPrank();

        // Consume in order
        vm.startPrank(USER);
        assertEq(vrf.getRandomness(), uint256(BETA_0));
        assertEq(vrf.getRandomness(), uint256(BETA_1));
        assertEq(vrf.getRandomness(), uint256(BETA_2));
        vm.stopPrank();

        assertEq(vrf.consumeNonce(), 3);
    }

    function test_getRandomness_revertNoAvailable() public {
        vm.prank(USER);
        vm.expectRevert(PredeployedVRF.NoRandomnessAvailable.selector);
        vrf.getRandomness();
    }

    function test_getRandomness_revertExhausted() public {
        // Commit one, consume one, then try again
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        vm.prank(USER);
        vrf.getRandomness(); // consume

        vm.prank(USER);
        vm.expectRevert(PredeployedVRF.NoRandomnessAvailable.selector);
        vrf.getRandomness(); // no more available
    }

    function test_getRandomness_anyoneCanCall() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Different users can consume
        vm.prank(address(0x1111));
        uint256 r = vrf.getRandomness();
        assertEq(r, uint256(BETA_0));
    }

    // ========== getResult ==========

    function test_getResult_success() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        (bytes32 seed, bytes32 beta, bytes memory storedPi) = vrf.getResult(0);
        assertEq(seed, SEED_0);
        assertEq(beta, BETA_0);
        assertEq(keccak256(storedPi), keccak256(pi));
    }

    function test_getResult_historical() public {
        bytes memory pi = _samplePi();

        vm.startPrank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);
        vrf.commitRandomness(1, SEED_1, BETA_1, pi);
        vm.stopPrank();

        // Both are retrievable
        (, bytes32 beta0,) = vrf.getResult(0);
        (, bytes32 beta1,) = vrf.getResult(1);

        assertEq(beta0, BETA_0);
        assertEq(beta1, BETA_1);
    }

    function test_getResult_revertNonceNotCommitted() public {
        vm.expectRevert(PredeployedVRF.NonceNotCommitted.selector);
        vrf.getResult(0);
    }

    function test_getResult_revertFutureNonce() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        vm.expectRevert(PredeployedVRF.NonceNotCommitted.selector);
        vrf.getResult(1); // only nonce 0 committed
    }

    function test_getResult_stillAvailableAfterConsume() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        // Consume
        vm.prank(USER);
        vrf.getRandomness();

        // Historical query still works
        (, bytes32 beta,) = vrf.getResult(0);
        assertEq(beta, BETA_0);
    }

    // ========== Nonce Tracking ==========

    function test_nonceTracking() public {
        assertEq(vrf.commitNonce(), 0);
        assertEq(vrf.consumeNonce(), 0);

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        assertEq(vrf.commitNonce(), 1);
        assertEq(vrf.consumeNonce(), 0);

        vm.prank(USER);
        vrf.getRandomness();

        assertEq(vrf.commitNonce(), 1);
        assertEq(vrf.consumeNonce(), 1);
    }

    // ========== Initial State ==========

    function test_initialState() public view {
        assertEq(vrf.commitNonce(), 0);
        assertEq(vrf.consumeNonce(), 0);
        assertEq(vrf.sequencerPublicKey().length, 0);
    }

    // ========== Integration: CoinFlip Example ==========

    function test_coinFlipExample() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        CoinFlip coinFlip = new CoinFlip(address(vrf));

        // The result is deterministic based on BETA_0
        bool heads = coinFlip.flip();
        bool expectedHeads = (uint256(BETA_0) % 2 == 0);
        assertEq(heads, expectedHeads);
    }

    // ========== Batch Commit and Consume ==========

    function test_batchCommitAndConsume() public {
        bytes memory pi = _samplePi();
        uint256 batchSize = 50;

        // Commit batch
        vm.startPrank(DEPOSITOR);
        for (uint256 i = 0; i < batchSize; i++) {
            bytes32 beta = keccak256(abi.encodePacked("beta", i));
            bytes32 seed = keccak256(abi.encodePacked("seed", i));
            vrf.commitRandomness(i, seed, beta, pi);
        }
        vm.stopPrank();

        assertEq(vrf.commitNonce(), batchSize);

        // Consume batch
        vm.startPrank(USER);
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 r = vrf.getRandomness();
            assertEq(r, uint256(keccak256(abi.encodePacked("beta", i))));
        }
        vm.stopPrank();

        assertEq(vrf.consumeNonce(), batchSize);
    }

    // ========== Gas Measurement ==========

    function test_gasCommitRandomness() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        uint256 gasBefore = gasleft();
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);
        uint256 gasUsed = gasBefore - gasleft();

        // Log for report
        emit log_named_uint("commitRandomness gas", gasUsed);
    }

    function test_gasGetRandomness() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        vrf.getRandomness();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("getRandomness gas", gasUsed);
    }

    function test_gasGetResult() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        uint256 gasBefore = gasleft();
        vrf.getResult(0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("getResult gas", gasUsed);
    }
}

/// @notice Minimal CoinFlip contract for integration testing.
contract CoinFlip {
    IEnshrainedVRF immutable vrfContract;

    constructor(address _vrf) {
        vrfContract = IEnshrainedVRF(_vrf);
    }

    function flip() external returns (bool heads) {
        uint256 randomness = vrfContract.getRandomness();
        heads = (randomness % 2 == 0);
    }
}
