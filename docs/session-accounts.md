# Session Accounts — Design Document

**Version**: 0.1 (draft)
**Date**: 2026-04-20
**Status**: Proposal

---

## 1. Motivation

Players should sign **once** when funding a game session and sign **nothing** during gameplay. This document specifies the account model, predeploys, and transaction flow that enable this on the enshrined-vrf L2.

Non-goals (this document):
- Full RIP-7560 native AA transaction type (deferred to later phase)
- Cross-game asset transfers
- Social recovery / multisig on Hub accounts

---

## 2. Account Model

Three layers:

```
┌─ EOA (main wallet, full custody) ──────────────────────────┐
│     │                                                       │
│     │ deposit + register session (signed once)             │
│     ▼                                                       │
│  GameHub Account (per user, smart contract)                │
│     │   - holds funds                                      │
│     │   - tracks per-game balance slots                    │
│     │   - validates session-key signatures                 │
│     │                                                       │
│     ├─ SessionKey_A ──▶ Game A contract only              │
│     ├─ SessionKey_B ──▶ Game B contract only              │
│     └─ SessionKey_C ──▶ Game C contract only              │
└─────────────────────────────────────────────────────────────┘
```

**Invariants:**
- One GameHub per EOA (deterministic CREATE2 address).
- Session keys can only call registered game contracts.
- Session keys cannot withdraw funds to external addresses — only main EOA can.
- Each session key has: `(gameAddr, spendingCap, expiry, allowedSelectors[])`.

---

## 3. Predeploys

| Address (TBD) | Contract              | Role                                                               |
|---------------|-----------------------|--------------------------------------------------------------------|
| `0x42...F0`   | `EnshrainedVRF`       | (existing) randomness source for all games                         |
| `0x42...A0`   | `GameHubFactory`      | CREATE2-deploys GameHub per EOA; deterministic lookup              |
| `0x42...A1`   | `SessionKeyManager`   | Register / revoke / query session keys per Hub                     |
| `0x42...A2`   | `GameRegistry`        | Whitelist of contracts recognized as "games"                       |
| `0x42...A3`   | `GamePaymaster`       | (optional, phase 3) sponsors gas for registered games              |

Addresses follow the existing predeploy prefix convention; exact values assigned before implementation.

---

## 4. Transaction Lifecycle

### 4.1 Deposit + session creation (one signature)

```
EOA signs 1 tx:
  GameHubFactory.depositAndRegister{value: X}(
    sessionPubKey,
    gameAddr,
    spendingCap,
    expiry,
    allowedSelectors
  )

Effects:
  1. Deploy Hub if not exists (CREATE2)
  2. Credit Hub.balances[gameAddr] += X
  3. SessionKeyManager.register(hub, sessionKey, scope)
```

### 4.2 Gameplay (zero signatures from main key)

```
Client signs with session key only → submits to sequencer
  Hub.execute(gameAddr, calldata)
    ├─ SessionKeyManager.validate(hub, signer, gameAddr, selector, value)
    ├─ GameRegistry.isRegistered(gameAddr) == true
    ├─ Hub.balances[gameAddr] -= value (if any)
    └─ CALL gameAddr with calldata
```

### 4.3 Withdrawal (main EOA only)

```
EOA signs:
  Hub.withdraw(gameAddr, amount, to)
    └─ requires msg.sender == hub.owner (not a session key)
```

Optional challenge period (TBD) to mitigate compromised main keys.

---

## 5. Interface Sketch

```solidity
interface IGameHub {
    function owner() external view returns (address);
    function balances(address game) external view returns (uint256);
    function execute(address game, bytes calldata data) external payable;
    function withdraw(address game, uint256 amount, address to) external;
}

interface ISessionKeyManager {
    struct Scope {
        address gameAddr;
        uint256 spendingCap;
        uint64  expiry;
        bytes4[] allowedSelectors; // empty = any selector on gameAddr
    }
    function register(address hub, address sessionKey, Scope calldata scope) external;
    function revoke(address hub, address sessionKey) external;
    function validate(
        address hub,
        address signer,
        address gameAddr,
        bytes4 selector,
        uint256 value
    ) external view returns (bool);
}

interface IGameRegistry {
    function register(address game) external;     // called by game deployer
    function isRegistered(address game) external view returns (bool);
}
```

Final interface may change after prototype.

---

## 6. Open Questions

| # | Question | Impact |
|---|----------|--------|
| 1 | Session key signature scheme: ECDSA only, or include passkey (secp256r1)? | Affects client SDK + validation gas |
| 2 | Withdrawal challenge period: none / fixed / configurable per Hub? | Security vs. UX tradeoff |
| 3 | Does Paymaster ship in phase 1 or defer? | Phase scope |
| 4 | Session key per-game vs. multi-game scope? | `Scope` struct shape |
| 5 | Can game contracts revoke their own session keys? (e.g., anti-cheat) | Trust model for games |
| 6 | How does this interact with EIP-7702? Hub as delegation target? | Integration path for existing EOAs |
| 7 | Nonce model for session keys: per-key sequential or 2D (RIP-7712 style)? | Parallel tx submission |
| 8 | Off-chain session key storage: browser local storage? Passkey-derived? | UX + security boundary |

---

## 7. Implementation Phases

**Phase 1 — Solidity prototype (`contracts/src/aa/`)**
- `GameHubAccount.sol`, `SessionKeyManager.sol`, `GameRegistry.sol`, `GameHubFactory.sol`
- `MockGame.sol` using `EnshrainedVRF`
- Foundry tests covering the three lifecycle flows (4.1–4.3)

**Phase 2 — E2E demo**
- Browser demo in `demo/` exercising deposit → session → play → withdraw
- Validates UX goal: one signature, then silent gameplay

**Phase 3 — EIP-7702 integration**
- Allow existing EOAs to delegate to `GameHubAccount` implementation
- Eliminates the separate-address mental model for users who want it

**Phase 4 — Enshrine to op-geth**
- Convert the four contracts above to predeploys (hardcoded at genesis)
- Consider native AA tx type (RIP-7560) only if gas / sequencer ergonomics require it

**Phase 5 — Paymaster (optional)**
- `GamePaymaster` predeploy for game-sponsored gas

---

## 8. Decisions Locked by This Document

- Three-layer account model (EOA → GameHub → SessionKeys).
- One Hub per user, not per game.
- `GameRegistry` gates which contracts session keys may call.
- Session keys cannot withdraw; only main EOA can.
- Contract-first implementation; protocol-level enshrining deferred to Phase 4.

Any deviation from the above should amend this document before code changes.
