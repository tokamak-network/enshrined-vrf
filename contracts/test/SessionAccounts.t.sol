// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GameRegistry} from "../src/aa/GameRegistry.sol";
import {SessionKeyManager} from "../src/aa/SessionKeyManager.sol";
import {GameHubAccount} from "../src/aa/GameHubAccount.sol";
import {GameHubFactory} from "../src/aa/GameHubFactory.sol";
import {DrawGame} from "../src/aa/examples/DrawGame.sol";
import {MockVRF} from "../src/mocks/MockVRF.sol";

/// @dev Minimal game contract used by the tests. Self-registers on deploy.
contract MockGame {
    GameRegistry public immutable registry;
    uint256 public plays;
    uint256 public received;

    constructor(GameRegistry reg) {
        registry = reg;
        reg.register();
    }

    function play() external payable {
        plays += 1;
        received += msg.value;
    }

    function betFail() external payable {
        revert("nope");
    }
}

contract SessionAccountsTest is Test {
    GameRegistry registry;
    SessionKeyManager skm;
    GameHubFactory factory;
    MockGame gameA;
    MockGame gameB;

    uint256 ownerPk = 0xA11CE;
    address owner;

    uint256 sessionPk = 0xB0B;
    address sessionKey;

    function setUp() public {
        owner = vm.addr(ownerPk);
        sessionKey = vm.addr(sessionPk);

        registry = new GameRegistry();
        skm = new SessionKeyManager();
        factory = new GameHubFactory(skm, registry);

        // tx.origin must equal owner when a game self-registers (for ownerOf()).
        // Not required for the tests that follow — just use default origin.
        gameA = new MockGame(registry);
        gameB = new MockGame(registry);

        vm.deal(owner, 100 ether);
    }

    // ── deposit + register ────────────────────────────────────────────

    function test_depositAndRegister_deploysHub_creditsBalance_registersKey() public {
        SessionKeyManager.Scope memory scope = SessionKeyManager.Scope({
            gameAddr: address(gameA),
            spendingCap: 1 ether,
            expiry: uint64(block.timestamp + 1 days),
            selectors: new bytes4[](0)
        });

        address expected = factory.hubOf(owner);
        assertEq(expected.code.length, 0, "hub should not exist yet");

        vm.prank(owner);
        address hubAddr = factory.depositAndRegister{value: 1 ether}(sessionKey, scope);

        assertEq(hubAddr, expected);
        assertGt(hubAddr.code.length, 0, "hub deployed");

        GameHubAccount hub = GameHubAccount(payable(hubAddr));
        assertEq(hub.owner(), owner);
        assertEq(hub.balances(address(gameA)), 1 ether);
        assertTrue(skm.isActive(hubAddr, sessionKey));
    }

    function test_depositAndRegister_secondCall_reusesHub() public {
        SessionKeyManager.Scope memory scope = _scope(address(gameA), 1 ether, 0);

        vm.prank(owner);
        address hub1 = factory.depositAndRegister{value: 0.5 ether}(sessionKey, scope);

        // Second session key on the same Hub
        address sessionKey2 = vm.addr(0xC0C0);
        SessionKeyManager.Scope memory scope2 = _scope(address(gameB), 0.5 ether, 0);
        vm.prank(owner);
        address hub2 = factory.depositAndRegister{value: 0.5 ether}(sessionKey2, scope2);

        assertEq(hub1, hub2, "same EOA same Hub");
        GameHubAccount hub = GameHubAccount(payable(hub1));
        assertEq(hub.balances(address(gameA)), 0.5 ether);
        assertEq(hub.balances(address(gameB)), 0.5 ether);
    }

    // ── session execution ─────────────────────────────────────────────

    function test_executeAsSession_succeeds_withinScope() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, uint64(block.timestamp + 1 days));

        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(gameA), 0.1 ether, data, nonce);

        // Anyone (relayer) can submit — not owner.
        vm.prank(address(0xDEAD));
        hub.executeAsSession(sessionKey, address(gameA), 0.1 ether, data, nonce, sig);

        assertEq(gameA.plays(), 1);
        assertEq(gameA.received(), 0.1 ether);
        assertEq(hub.balances(address(gameA)), 0.9 ether);
        assertEq(skm.scopeOf(address(hub), sessionKey).spendingCap, 0.9 ether);
        assertEq(hub.sessionNonce(sessionKey), 1);
    }

    function test_executeAsSession_rejects_wrongGame() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        // Scope is for gameA; try to call gameB.
        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(gameB), 0, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(gameB), 0, data, nonce, sig);
    }

    function test_executeAsSession_rejects_overCap() public {
        GameHubAccount hub = _setupHub(address(gameA), 0.5 ether, 0);
        // deposit extra so balance check doesn't trip first
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        hub.deposit{value: 1 ether}(address(gameA));

        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(gameA), 1 ether, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(gameA), 1 ether, data, nonce, sig);
    }

    function test_executeAsSession_rejects_expired() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, exp);

        vm.warp(exp + 1);

        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(gameA), 0, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(gameA), 0, data, nonce, sig);
    }

    function test_executeAsSession_rejects_badNonce() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        bytes memory data = abi.encodeCall(MockGame.play, ());
        bytes memory sig = _signSession(hub, sessionKey, address(gameA), 0, data, 99);

        vm.expectRevert(GameHubAccount.BadNonce.selector);
        hub.executeAsSession(sessionKey, address(gameA), 0, data, 99, sig);
    }

    function test_executeAsSession_rejects_unregisteredSigner() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        uint256 evilPk = 0xEE;
        address evil = vm.addr(evilPk);

        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(evil);
        bytes memory sig = _signSessionRaw(evilPk, hub, evil, address(gameA), 0, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(evil, address(gameA), 0, data, nonce, sig);
    }

    function test_revoke_blocksFurtherUse() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        vm.prank(owner);
        hub.revokeSession(sessionKey);

        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(gameA), 0, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(gameA), 0, data, nonce, sig);
    }

    // ── withdraw ──────────────────────────────────────────────────────

    function test_withdraw_ownerOnly() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        address payable recipient = payable(address(0xCAFE));
        uint256 before = recipient.balance;

        vm.prank(owner);
        hub.withdraw(address(gameA), 0.3 ether, recipient);

        assertEq(recipient.balance - before, 0.3 ether);
        assertEq(hub.balances(address(gameA)), 0.7 ether);
    }

    function test_withdraw_sessionKeyCannot() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        // Even calling via executeAsSession, the Hub.withdraw target will
        // check msg.sender == owner. But session keys can't target the Hub
        // itself because the Hub is not a registered game.
        bytes memory data = abi.encodeCall(
            GameHubAccount.withdraw,
            (address(gameA), 0.1 ether, payable(sessionKey))
        );
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(hub), 0, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(hub), 0, data, nonce, sig);
    }

    // ── refill ────────────────────────────────────────────────────────

    function test_refill_increasesCap_allowsMorePlays() public {
        GameHubAccount hub = _setupHub(address(gameA), 0.02 ether, 0);

        // Use both slots of initial cap.
        _sessionPlay(hub, address(gameA), 0.01 ether);
        _sessionPlay(hub, address(gameA), 0.01 ether);

        // Now at cap 0. Refill with +0.03 and additional deposit.
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        factory.depositAndRefill{value: 0.03 ether}(sessionKey, address(gameA), 0.03 ether, 0);

        assertEq(skm.scopeOf(address(hub), sessionKey).spendingCap, 0.03 ether);
        assertEq(hub.balances(address(gameA)), 0.03 ether);

        // Three more plays should now succeed.
        _sessionPlay(hub, address(gameA), 0.01 ether);
        _sessionPlay(hub, address(gameA), 0.01 ether);
        _sessionPlay(hub, address(gameA), 0.01 ether);
        assertEq(gameA.plays(), 5);
    }

    function test_refill_extendsExpiry_revivesExpiredSession() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, exp);

        vm.warp(exp + 10); // session has expired

        // Sanity: pre-refill call rejected.
        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(gameA), 0, data, nonce);
        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(gameA), 0, data, nonce, sig);

        // Refill with new expiry; no added cap, no value.
        uint64 newExp = uint64(block.timestamp + 1 hours);
        vm.prank(owner);
        factory.depositAndRefill(sessionKey, address(gameA), 0, newExp);
        assertEq(skm.scopeOf(address(hub), sessionKey).expiry, newExp);

        // Same session now works.
        _sessionPlay(hub, address(gameA), 0);
        assertEq(gameA.plays(), 1);
    }

    function test_refill_revokedSession_reverts() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        vm.prank(owner);
        hub.revokeSession(sessionKey);

        vm.prank(owner);
        vm.expectRevert(); // factory/refill-failed wrapping NotActive
        factory.depositAndRefill(sessionKey, address(gameA), 0.01 ether, 0);
    }

    function test_refill_notOwner_reverts() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        vm.prank(address(0xBAD));
        vm.expectRevert(GameHubAccount.NotOwner.selector);
        hub.refillSession(sessionKey, address(gameA), 0.01 ether, 0);
    }

    function test_refill_invalidExpiry_reverts() public {
        GameHubAccount hub = _setupHub(address(gameA), 1 ether, 0);

        vm.prank(owner);
        vm.expectRevert(); // factory/refill-failed wrapping InvalidExpiry
        factory.depositAndRefill(sessionKey, address(gameA), 0, uint64(block.timestamp));
    }

    // ── E2E: VRF-backed game via session key ─────────────────────────

    function test_e2e_drawGame_viaSessionKey() public {
        MockVRF vrf = new MockVRF();
        DrawGame draw = new DrawGame(registry, vrf);

        // Session authorized to call DrawGame, restricted to draw() selector.
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DrawGame.draw.selector;
        SessionKeyManager.Scope memory scope = SessionKeyManager.Scope({
            gameAddr: address(draw),
            spendingCap: 0.05 ether,
            expiry: uint64(block.timestamp + 1 hours),
            selectors: sels
        });

        vm.prank(owner);
        address hubAddr = factory.depositAndRegister{value: 0.05 ether}(sessionKey, scope);
        GameHubAccount hub = GameHubAccount(payable(hubAddr));

        // 5 draws, each costs BET = 0.01 ether, all signed by the session key
        // (no owner signatures after onboarding).
        for (uint256 i; i < 5; ++i) {
            bytes memory data = abi.encodeCall(DrawGame.draw, ());
            uint256 nonce = hub.sessionNonce(sessionKey);
            bytes memory sig = _signSession(
                hub, sessionKey, address(draw), draw.BET(), data, nonce
            );

            // Relayer submits — anyone can be msg.sender here.
            vm.prank(address(0xBEEF));
            hub.executeAsSession(sessionKey, address(draw), draw.BET(), data, nonce, sig);
        }

        assertEq(hub.balances(address(draw)), 0, "all BET consumed");
        assertEq(vrf.callCounter(), 5, "5 VRF draws");
        assertEq(skm.scopeOf(hubAddr, sessionKey).spendingCap, 0, "cap exhausted");
        assertEq(hub.sessionNonce(sessionKey), 5);
    }

    function test_e2e_drawGame_selectorEnforced() public {
        MockVRF vrf = new MockVRF();
        DrawGame draw = new DrawGame(registry, vrf);

        // Session key only authorized for a selector that doesn't exist on DrawGame.
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = bytes4(keccak256("somethingElse()"));
        SessionKeyManager.Scope memory scope = SessionKeyManager.Scope({
            gameAddr: address(draw),
            spendingCap: 0.05 ether,
            expiry: 0,
            selectors: sels
        });

        vm.prank(owner);
        address hubAddr = factory.depositAndRegister{value: 0.05 ether}(sessionKey, scope);
        GameHubAccount hub = GameHubAccount(payable(hubAddr));

        uint256 bet = draw.BET();
        bytes memory data = abi.encodeCall(DrawGame.draw, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, address(draw), bet, data, nonce);

        vm.expectRevert(GameHubAccount.Unauthorized.selector);
        hub.executeAsSession(sessionKey, address(draw), bet, data, nonce, sig);
    }

    // ── registry gating ───────────────────────────────────────────────

    function test_depositAndRegister_rejects_unregisteredGame() public {
        address bogus = address(0xB0605);
        SessionKeyManager.Scope memory scope = _scope(bogus, 1 ether, 0);

        vm.prank(owner);
        vm.expectRevert(); // factory/deposit-failed — GameNotRegistered
        factory.depositAndRegister{value: 1 ether}(sessionKey, scope);
    }

    // ── helpers ───────────────────────────────────────────────────────

    function _scope(address game, uint256 cap, uint64 expiry)
        internal
        pure
        returns (SessionKeyManager.Scope memory s)
    {
        s.gameAddr = game;
        s.spendingCap = cap;
        s.expiry = expiry;
        s.selectors = new bytes4[](0);
    }

    function _setupHub(address game, uint256 cap, uint64 expiry)
        internal
        returns (GameHubAccount hub)
    {
        SessionKeyManager.Scope memory scope = _scope(game, cap, expiry);
        vm.prank(owner);
        address hubAddr = factory.depositAndRegister{value: cap}(sessionKey, scope);
        hub = GameHubAccount(payable(hubAddr));
    }

    function _sessionPlay(GameHubAccount hub, address game, uint256 value) internal {
        bytes memory data = abi.encodeCall(MockGame.play, ());
        uint256 nonce = hub.sessionNonce(sessionKey);
        bytes memory sig = _signSession(hub, sessionKey, game, value, data, nonce);
        hub.executeAsSession(sessionKey, game, value, data, nonce, sig);
    }

    function _signSession(
        GameHubAccount hub,
        address signer,
        address game,
        uint256 value,
        bytes memory data,
        uint256 nonce
    ) internal view returns (bytes memory) {
        return _signSessionRaw(sessionPk, hub, signer, game, value, data, nonce);
    }

    function _signSessionRaw(
        uint256 pk,
        GameHubAccount hub,
        address signer,
        address game,
        uint256 value,
        bytes memory data,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 inner = keccak256(
            abi.encode(address(hub), block.chainid, signer, game, value, keccak256(data), nonce)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
