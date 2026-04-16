// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {EnshrainedVRF} from "optimism/src/L2/EnshrainedVRF.sol";
import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

contract EnshrainedVRFTest is Test {
    EnshrainedVRF public vrf;

    event RandomnessCommitted(uint256 indexed nonce, bytes32 beta, address indexed caller);

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
        vrf = new EnshrainedVRF();
        vm.etch(PREDEPLOY_ADDR, address(vrf).code);
        vrf = EnshrainedVRF(PREDEPLOY_ADDR);
    }

    // ========== CONSTANTS ==========

    function test_depositorAccountAddress() public view {
        assertEq(vrf.DEPOSITOR_ACCOUNT(), DEPOSITOR);
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
        vm.expectRevert(EnshrainedVRF.OnlyDepositor.selector);
        vrf.setSequencerPublicKey(SAMPLE_PK);
    }

    function test_setSequencerPublicKey_revertInvalidLength() public {
        vm.prank(DEPOSITOR);
        vm.expectRevert(EnshrainedVRF.InvalidPublicKeyLength.selector);
        vrf.setSequencerPublicKey(hex"0102"); // 2 bytes, not 33
    }

    function test_setSequencerPublicKey_revertInvalidLength65() public {
        vm.prank(DEPOSITOR);
        bytes memory uncompressed = new bytes(65);
        vm.expectRevert(EnshrainedVRF.InvalidPublicKeyLength.selector);
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
        emit RandomnessCommitted(0, BETA_0, DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);
    }

    function test_commitRandomness_revertNotDepositor() public {
        vm.prank(USER);
        vm.expectRevert(EnshrainedVRF.OnlyDepositor.selector);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());
    }

    function test_commitRandomness_revertInvalidProofLength() public {
        vm.prank(DEPOSITOR);
        vm.expectRevert(EnshrainedVRF.InvalidProofLength.selector);
        vrf.commitRandomness(0, SEED_0, BETA_0, hex"0102"); // 2 bytes, not 81
    }

    function test_commitRandomness_sequential() public {
        bytes memory pi = _samplePi();

        vm.roll(1);
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        vm.roll(2);
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(1, SEED_1, BETA_1, pi);

        vm.roll(3);
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(2, SEED_2, BETA_2, pi);

        assertEq(vrf.commitNonce(), 3);
    }

    function test_commitRandomness_resetsCallCounter() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Call getRandomness twice to increment counter
        vm.prank(USER);
        vrf.getRandomness();
        vm.prank(USER);
        vrf.getRandomness();
        assertEq(vrf.callCounter(), 2);

        // New block, new commitment resets counter
        vm.roll(block.number + 1);
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(1, SEED_1, BETA_1, _samplePi());
        assertEq(vrf.callCounter(), 0);
    }

    // ========== getRandomness ==========

    function test_getRandomness_derivesFromBeta() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        vm.prank(USER);
        uint256 randomness = vrf.getRandomness();

        // First call: keccak256(BETA_0, 0)
        uint256 expected = uint256(keccak256(abi.encodePacked(BETA_0, uint256(0))));
        assertEq(randomness, expected);
    }

    function test_getRandomness_uniquePerCall() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        vm.prank(USER);
        uint256 r0 = vrf.getRandomness();
        vm.prank(USER);
        uint256 r1 = vrf.getRandomness();
        vm.prank(USER);
        uint256 r2 = vrf.getRandomness();

        // All different
        assertTrue(r0 != r1);
        assertTrue(r1 != r2);
        assertTrue(r0 != r2);

        // Verify derivation
        assertEq(r0, uint256(keccak256(abi.encodePacked(BETA_0, uint256(0)))));
        assertEq(r1, uint256(keccak256(abi.encodePacked(BETA_0, uint256(1)))));
        assertEq(r2, uint256(keccak256(abi.encodePacked(BETA_0, uint256(2)))));
    }

    function test_getRandomness_revertNoCommitmentForBlock() public {
        // No commitment at all
        vm.prank(USER);
        vm.expectRevert(EnshrainedVRF.NoRandomnessAvailable.selector);
        vrf.getRandomness();
    }

    function test_getRandomness_revertDifferentBlock() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Advance to next block — commitment was for the previous block
        vm.roll(block.number + 1);

        vm.prank(USER);
        vm.expectRevert(EnshrainedVRF.NoRandomnessAvailable.selector);
        vrf.getRandomness();
    }

    function test_getRandomness_unlimitedCallsPerBlock() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Can call many times in the same block without reverting
        uint256 prev;
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(USER);
            uint256 r = vrf.getRandomness();
            assertTrue(r != prev);
            prev = r;
        }
        assertEq(vrf.callCounter(), 100);
    }

    function test_getRandomness_anyoneCanCall() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Different users get different values (different callCounter)
        vm.prank(address(0x1111));
        uint256 r0 = vrf.getRandomness();
        vm.prank(address(0x2222));
        uint256 r1 = vrf.getRandomness();

        assertTrue(r0 != r1);
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

        vm.roll(1);
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);

        vm.roll(2);
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(1, SEED_1, BETA_1, pi);

        // Both are retrievable
        (, bytes32 beta0,) = vrf.getResult(0);
        (, bytes32 beta1,) = vrf.getResult(1);

        assertEq(beta0, BETA_0);
        assertEq(beta1, BETA_1);
    }

    function test_getResult_revertNonceNotCommitted() public {
        vm.expectRevert(EnshrainedVRF.NonceNotCommitted.selector);
        vrf.getResult(0);
    }

    function test_getResult_revertFutureNonce() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        vm.expectRevert(EnshrainedVRF.NonceNotCommitted.selector);
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

    // ========== Counter Tracking ==========

    function test_counterTracking() public {
        assertEq(vrf.commitNonce(), 0);
        assertEq(vrf.callCounter(), 0);

        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        assertEq(vrf.commitNonce(), 1);
        assertEq(vrf.callCounter(), 0);

        vm.prank(USER);
        vrf.getRandomness();

        assertEq(vrf.commitNonce(), 1);
        assertEq(vrf.callCounter(), 1);
    }

    // ========== Initial State ==========

    function test_initialState() public view {
        assertEq(vrf.commitNonce(), 0);
        assertEq(vrf.callCounter(), 0);
        assertEq(vrf.sequencerPublicKey().length, 0);
    }

    // ========== Integration: CoinFlip Example ==========

    function test_coinFlipExample() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        CoinFlip coinFlip = new CoinFlip(address(vrf));

        // The result is deterministic based on keccak256(BETA_0, 0)
        bool heads = coinFlip.flip();
        uint256 derived = uint256(keccak256(abi.encodePacked(BETA_0, uint256(0))));
        bool expectedHeads = (derived % 2 == 0);
        assertEq(heads, expectedHeads);
    }

    // ========== Multiple Calls Per Block (core new behavior) ==========

    function test_multipleUsersPerBlock() public {
        vm.prank(DEPOSITOR);
        vrf.commitRandomness(0, SEED_0, BETA_0, _samplePi());

        // Three different contracts/users calling in the same block
        CoinFlip flip1 = new CoinFlip(address(vrf));
        CoinFlip flip2 = new CoinFlip(address(vrf));
        CoinFlip flip3 = new CoinFlip(address(vrf));

        flip1.flip(); // counter 0
        flip2.flip(); // counter 1
        flip3.flip(); // counter 2

        assertEq(vrf.callCounter(), 3);
    }

    // ========== Gas Measurement ==========

    function test_gasCommitRandomness() public {
        bytes memory pi = _samplePi();

        vm.prank(DEPOSITOR);
        uint256 gasBefore = gasleft();
        vrf.commitRandomness(0, SEED_0, BETA_0, pi);
        uint256 gasUsed = gasBefore - gasleft();

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
