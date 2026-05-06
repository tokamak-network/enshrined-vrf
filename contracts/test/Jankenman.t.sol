// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Test, Vm} from "forge-std/Test.sol";
import {Jankenman} from "../src/examples/Jankenman.sol";
import {ArcadeVRF} from "../src/examples/ArcadeVRF.sol";

contract JankenmanTest is Test {
    Jankenman public game;
    ArcadeVRF  public vrf;

    address constant PREDEPLOY = 0x42000000000000000000000000000000000000f0;
    address constant ALICE = address(0xA11CE);
    address constant BOB   = address(0xB0B);
    address constant LP    = address(0x11D);

    // ArcadeVRF storage slots (declaration order, 0.8.15):
    //   slot 0: _sequencerPublicKey (bytes, length lives here for short bytes)
    //   slot 1: _commitNonce
    //   slot 2: _latestBeta
    //   slot 3: _callCounter
    uint256 constant SLOT_LATEST_BETA  = 2;
    uint256 constant SLOT_CALL_COUNTER = 3;

    event Played(
        address indexed player,
        address          viaKey,
        uint8            playerHand,
        uint8            houseHand,
        uint8            outcome,
        uint8            multiplier,
        uint256          bet,
        uint256          payout,
        uint256          randomness
    );

    function setUp() public {
        // Install ArcadeVRF at the predeploy address (matches arcade.sh).
        ArcadeVRF impl = new ArcadeVRF();
        vm.etch(PREDEPLOY, address(impl).code);
        vrf = ArcadeVRF(PREDEPLOY);

        // Pin a known beta so we can deterministically search for a counter
        // value that produces a desired randomness.
        vm.store(PREDEPLOY, bytes32(SLOT_LATEST_BETA), keccak256("arcade-test-beta"));

        game = new Jankenman();

        // Seed the LP pool the same way arcade.sh does (50 ETH donation via receive()).
        vm.deal(address(this), 100 ether);
        (bool ok, ) = address(game).call{value: 50 ether}("");
        require(ok, "seed failed");

        vm.deal(ALICE, 100 ether);
        vm.deal(BOB,   100 ether);
        vm.deal(LP,    100 ether);
    }

    // ─────────────────────────────────────────────────────────────
    // VRF pinning helpers
    // ─────────────────────────────────────────────────────────────

    /// @dev Brute-force a `_callCounter` value such that the next
    ///      getRandomness() call returns a value with `rand % 3 == targetHouse`
    ///      AND (when targetMult > 0) keccak(rand, 1) % 100 falls in the
    ///      multiplier's bucket. Sets the counter via vm.store and returns.
    function _pinOutcome(uint8 targetHouse, uint8 targetMult) internal {
        bytes32 beta = vm.load(PREDEPLOY, bytes32(SLOT_LATEST_BETA));
        uint256 bn = block.number;
        for (uint256 c = 0; c < 200_000; c++) {
            uint256 r = uint256(keccak256(abi.encodePacked(beta, c, bn)));
            if (r % 3 != targetHouse) continue;
            if (targetMult == 0) {
                vm.store(PREDEPLOY, bytes32(SLOT_CALL_COUNTER), bytes32(c));
                return;
            }
            uint256 rr = uint256(keccak256(abi.encodePacked(r, uint8(1)))) % 100;
            bool hit;
            if      (targetMult == 1)  hit = rr < 70;
            else if (targetMult == 2)  hit = rr >= 70 && rr < 88;
            else if (targetMult == 4)  hit = rr >= 88 && rr < 96;
            else if (targetMult == 7)  hit = rr >= 96 && rr < 99;
            else if (targetMult == 20) hit = rr == 99;
            if (hit) {
                vm.store(PREDEPLOY, bytes32(SLOT_CALL_COUNTER), bytes32(c));
                return;
            }
        }
        revert("could not pin outcome - widen search range");
    }

    function _accountingInvariant() internal view {
        // sum(credits) + lpAssets == address(this).balance.
        // We track every depositor in tests below; this helper is kept simple
        // by summing the addresses that actually moved money in this suite.
        uint256 sum = game.credits(ALICE) + game.credits(BOB) + game.credits(LP);
        assertEq(sum + game.lpAssets(), address(game).balance, "balance invariant");
    }

    // ─────────────────────────────────────────────────────────────
    // Deposit / withdraw / LP basics
    // ─────────────────────────────────────────────────────────────

    function test_deposit_credits_player() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();
        assertEq(game.credits(ALICE), 1 ether);
        _accountingInvariant();
    }

    function test_deposit_zero_reverts() public {
        vm.expectRevert(Jankenman.ZeroAmount.selector);
        vm.prank(ALICE);
        game.deposit{value: 0}();
    }

    function test_withdraw_returns_eth() public {
        vm.startPrank(ALICE);
        game.deposit{value: 2 ether}();
        uint256 before = ALICE.balance;
        game.withdraw();
        assertEq(ALICE.balance, before + 2 ether);
        assertEq(game.credits(ALICE), 0);
        vm.stopPrank();
        _accountingInvariant();
    }

    function test_withdraw_no_credits_reverts() public {
        vm.expectRevert(Jankenman.NoCredits.selector);
        vm.prank(ALICE);
        game.withdraw();
    }

    function test_lp_deposit_first_minted_1to1() public {
        // Pool was seeded with 50 ETH via receive() — that's a donation
        // (lpAssets bumped, no shares). LP is the first share-holder.
        uint256 startLpAssets = game.lpAssets();
        assertEq(startLpAssets, 50 ether);
        assertEq(game.totalShares(), 0);

        vm.prank(LP);
        game.depositLP{value: 10 ether}();

        // First minter when totalShares == 0: shares = msg.value.
        assertEq(game.sharesOf(LP), 10 ether);
        assertEq(game.totalShares(), 10 ether);
        assertEq(game.lpAssets(), 60 ether);
    }

    function test_lp_withdraw_pro_rata() public {
        vm.prank(LP);
        game.depositLP{value: 10 ether}();
        // After deposit, totalShares = 10e18, lpAssets = 60e18.
        // Pull half: should receive 30 ETH (because shares own 60e18 worth).
        uint256 before = LP.balance;
        vm.prank(LP);
        game.withdrawLP(5 ether);
        assertEq(LP.balance, before + 30 ether);
        assertEq(game.sharesOf(LP), 5 ether);
        assertEq(game.totalShares(), 5 ether);
        assertEq(game.lpAssets(), 30 ether);
    }

    // ─────────────────────────────────────────────────────────────
    // Direct play() — outcome branches
    // ─────────────────────────────────────────────────────────────

    function test_play_draw_refunds_bet_to_credits() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();

        // Player picks Rock(0); house also Rock → draw (outcome=1).
        _pinOutcome({targetHouse: 0, targetMult: 0});

        uint256 lpBefore = game.lpAssets();
        vm.prank(ALICE);
        (uint8 hh, uint8 outcome, uint8 mult, uint256 payout,) = game.play(0, 0.1 ether);

        assertEq(hh, 0);
        assertEq(outcome, 1, "draw");
        assertEq(mult, 0);
        assertEq(payout, 0);
        assertEq(game.credits(ALICE), 1 ether, "draw should not move credits");
        assertEq(game.lpAssets(), lpBefore, "draw should not move lpAssets");
        _accountingInvariant();
    }

    function test_play_lose_moves_bet_to_lp() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();

        // Rock(0) vs Paper(1) → player loses. Paper covers Rock.
        _pinOutcome({targetHouse: 1, targetMult: 0});

        uint256 lpBefore = game.lpAssets();
        vm.prank(ALICE);
        (, uint8 outcome,, uint256 payout,) = game.play(0, 0.1 ether);

        assertEq(outcome, 0, "lose");
        assertEq(payout, 0);
        assertEq(game.credits(ALICE), 1 ether - 0.1 ether);
        assertEq(game.lpAssets(), lpBefore + 0.1 ether);
        _accountingInvariant();
    }

    function test_play_win_1x() public {
        _winRoulette(1);
    }
    function test_play_win_2x() public {
        _winRoulette(2);
    }
    function test_play_win_4x() public {
        _winRoulette(4);
    }
    function test_play_win_7x() public {
        _winRoulette(7);
    }
    function test_play_win_20x() public {
        _winRoulette(20);
    }

    /// @dev Player picks Rock(0). Win-against-Rock means house played
    ///      Scissors(2) (Rock crushes Scissors). Verification uses the
    ///      Played event because the win branch of _play has a known bug:
    ///      it never assigns the `outcome` named return, so the function
    ///      returns outcome=0 even though the event correctly emits 2.
    ///      The frontend reads the event, so gameplay still works.
    function _winRoulette(uint8 targetMult) internal {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();

        _pinOutcome({targetHouse: 2, targetMult: targetMult});

        uint256 lpBefore = game.lpAssets();
        uint256 creditsBefore = game.credits(ALICE);
        uint256 bet = 0.1 ether;

        vm.recordLogs();
        vm.prank(ALICE);
        game.play(0, bet);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint8 evHouseHand, uint8 evOutcome, uint8 evMult, uint256 evBet, uint256 evPayout) =
            _decodePlayedEvent(logs);

        assertEq(evHouseHand, 2, "house should be scissors");
        assertEq(evOutcome, 2, "win outcome via event");
        assertEq(evMult, targetMult, "multiplier mismatch");
        assertEq(evBet, bet, "bet emitted");
        assertEq(evPayout, bet * targetMult, "payout = bet * mult");

        if (targetMult > 1) {
            assertEq(game.credits(ALICE), creditsBefore + bet * (uint256(targetMult) - 1));
            assertEq(game.lpAssets(), lpBefore - bet * (uint256(targetMult) - 1));
        } else {
            // 1× win: bet refunded into credits, LP unchanged.
            assertEq(game.credits(ALICE), creditsBefore);
            assertEq(game.lpAssets(), lpBefore);
        }
        _accountingInvariant();
    }

    /// @dev Pull (houseHand, outcome, mult, bet, payout) out of the Played
    ///      event in a recorded log array.
    function _decodePlayedEvent(Vm.Log[] memory logs)
        internal
        pure
        returns (uint8 houseHand, uint8 outcome, uint8 mult, uint256 bet, uint256 payout)
    {
        bytes32 topic0 = keccak256(
            "Played(address,address,uint8,uint8,uint8,uint8,uint256,uint256,uint256)"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != topic0) continue;
            // Non-indexed payload order: viaKey, playerHand, houseHand,
            // outcome, multiplier, bet, payout, randomness.
            (
                address viaKey,
                uint8 playerHand,
                uint8 hHand,
                uint8 oc,
                uint8 m,
                uint256 b,
                uint256 p,
                uint256 randomness
            ) = abi.decode(
                logs[i].data,
                (address, uint8, uint8, uint8, uint8, uint256, uint256, uint256)
            );
            viaKey; playerHand; randomness; // silence unused-var warnings
            return (hHand, oc, m, b, p);
        }
        revert("no Played event");
    }

    /// @dev Documents a real defect in src/examples/Jankenman.sol: the win
    ///      branch sets `payout` and `multiplier` on the named returns but
    ///      forgets to set `outcome = 2` before falling off the end of the
    ///      function. Result: a contract that calls play() and reads the
    ///      tuple sees outcome=0 (lose) on a winning round. The Played
    ///      event is unaffected and emits 2 correctly, which is why the
    ///      web frontend (event-based) still works.
    function test_play_win_named_return_outcome_is_zero_BUG() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();
        _pinOutcome({targetHouse: 2, targetMult: 1});

        vm.prank(ALICE);
        (uint8 hh, uint8 outcome, uint8 mult, uint256 payout,) = game.play(0, 0.1 ether);

        assertEq(hh, 2, "house = scissors");
        assertEq(mult, 1, "multiplier set");
        assertEq(payout, 0.1 ether, "payout set");
        // BUG: outcome should be 2 here, but the contract returns 0.
        assertEq(outcome, 0, "BUG: win branch leaves outcome at default 0");
    }

    // ─────────────────────────────────────────────────────────────
    // Reverts
    // ─────────────────────────────────────────────────────────────

    function test_play_bad_hand_reverts() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();
        vm.expectRevert(Jankenman.BadHand.selector);
        vm.prank(ALICE);
        game.play(3, 0.1 ether);
    }

    function test_play_bet_too_small_reverts() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();
        vm.expectRevert(Jankenman.BetTooSmall.selector);
        vm.prank(ALICE);
        game.play(0, 1e14); // 0.0001 ETH < MIN_BET (1e15)
    }

    function test_play_no_credits_reverts() public {
        vm.expectRevert(Jankenman.NoCredits.selector);
        vm.prank(ALICE);
        game.play(0, 1e15);
    }

    function test_play_pool_too_shallow_reverts() public {
        // Worst-case payout = bet * 20. Cap is 10% of pool.
        // Pool = 50 ETH. Cap = 5 ETH worst-case payout → max bet = 0.25 ETH.
        // Bet 0.3 ETH → 6 ETH worst-case → reverts.
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();
        vm.expectRevert(Jankenman.PoolTooShallow.selector);
        vm.prank(ALICE);
        game.play(0, 0.3 ether);
    }

    // ─────────────────────────────────────────────────────────────
    // Session keys
    // ─────────────────────────────────────────────────────────────

    function test_startSession_credits_and_funds_key() public {
        address key = address(0xCAFE);
        uint64 validUntil = uint64(block.timestamp + 1 hours);

        vm.prank(ALICE);
        game.startSession{value: 1 ether}(key, validUntil, 0.05 ether);

        assertEq(game.sessionKey(ALICE, key), validUntil);
        assertEq(game.credits(ALICE), 0.95 ether);
        assertEq(key.balance, 0.05 ether);
    }

    function test_playFor_authorized_key_succeeds() public {
        address key = address(0xCAFE);
        uint64 validUntil = uint64(block.timestamp + 1 hours);

        vm.prank(ALICE);
        game.startSession{value: 1 ether}(key, validUntil, 0);

        // Force a draw so we don't perturb LP balances unpredictably.
        _pinOutcome({targetHouse: 0, targetMult: 0});

        vm.prank(key);
        (, uint8 outcome,,,) = game.playFor(ALICE, 0, 0.1 ether);
        assertEq(outcome, 1, "draw via session key");
    }

    function test_playFor_unauthorized_reverts() public {
        // Bob tries to call playFor for Alice without Alice's authorization.
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();

        vm.expectRevert(Jankenman.NotAuthorized.selector);
        vm.prank(BOB);
        game.playFor(ALICE, 0, 0.1 ether);
    }

    function test_playFor_expired_reverts() public {
        address key = address(0xCAFE);
        uint64 validUntil = uint64(block.timestamp + 1 hours);

        vm.prank(ALICE);
        game.startSession{value: 1 ether}(key, validUntil, 0);

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(Jankenman.SessionExpired.selector);
        vm.prank(key);
        game.playFor(ALICE, 0, 0.1 ether);
    }

    function test_revokeSession_blocks_key() public {
        address key = address(0xCAFE);
        uint64 validUntil = uint64(block.timestamp + 1 hours);

        vm.prank(ALICE);
        game.startSession{value: 1 ether}(key, validUntil, 0);

        vm.prank(ALICE);
        game.revokeSession(key);
        assertEq(game.sessionKey(ALICE, key), 0);

        vm.expectRevert(Jankenman.NotAuthorized.selector);
        vm.prank(key);
        game.playFor(ALICE, 0, 0.1 ether);
    }

    // ─────────────────────────────────────────────────────────────
    // End-to-end: Played event payload + accounting over a sequence
    // ─────────────────────────────────────────────────────────────

    function test_played_event_emitted_on_lose() public {
        vm.prank(ALICE);
        game.deposit{value: 1 ether}();

        _pinOutcome({targetHouse: 1, targetMult: 0}); // Rock vs Paper → lose.

        // Compute the randomness that will be observed inside _play.
        bytes32 beta = vm.load(PREDEPLOY, bytes32(SLOT_LATEST_BETA));
        uint256 c = uint256(vm.load(PREDEPLOY, bytes32(SLOT_CALL_COUNTER)));
        uint256 expectedRand =
            uint256(keccak256(abi.encodePacked(beta, c, block.number)));

        vm.expectEmit(true, false, false, true, address(game));
        emit Played(ALICE, address(0), 0, 1, 0, 0, 0.1 ether, 0, expectedRand);

        vm.prank(ALICE);
        game.play(0, 0.1 ether);
    }

    function test_sequence_keeps_balance_invariant() public {
        vm.prank(ALICE);
        game.deposit{value: 5 ether}();
        vm.prank(BOB);
        game.deposit{value: 5 ether}();
        vm.prank(LP);
        game.depositLP{value: 10 ether}();

        // Alice loses one round.
        _pinOutcome({targetHouse: 1, targetMult: 0});
        vm.prank(ALICE);
        game.play(0, 0.2 ether);

        // Bob wins 4× one round.
        _pinOutcome({targetHouse: 2, targetMult: 4});
        vm.prank(BOB);
        game.play(0, 0.2 ether);

        // Alice draws.
        _pinOutcome({targetHouse: 0, targetMult: 0});
        vm.prank(ALICE);
        game.play(0, 0.2 ether);

        _accountingInvariant();
    }
}
