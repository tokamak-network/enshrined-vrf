# Session scope exhaustion UX

**Area:** Session Accounts (Phase 1+)
**Status:** Proposal
**Related docs:** `docs/session-accounts.md`

## Summary

When a session key's `spendingCap` or `expiry` is reached, the current demo simply refuses the next `executeAsSession` call with `Unauthorized` and asks the user to start a brand new session. This is a hard wall mid-gameplay and contradicts the "sign once, play freely" promise we are optimizing for.

Define and ship a graceful exhaustion UX so that reaching the end of a session feels like a seamless top-up, not a game-stopping failure.

## Current behavior (baseline)

1. Hub's `executeAsSession` calls `SessionKeyManager.canCall`, which returns false when `value > spendingCap`, `block.timestamp >= expiry`, or the selector is not in the whitelist.
2. The call reverts with `Unauthorized()` (`0x82b42900`).
3. The browser demo pre-checks `spendingCap` before each draw and logs `stopped at N/M: session cap exhausted. Start a new session to continue.`
4. The user must click **Start Session** again, which:
   - Generates a new session key (old key's gas ETH is stranded).
   - Triggers 2 MetaMask popups: `depositAndRegister` + gas pre-fund.

This is fine as an invariant test. It is not a shippable player experience.

## Desired UX patterns

### 1. Cap meter + countdown in the UI

A non-blocking visual signal that remaining cap and time-to-expiry are getting low. The player should never be surprised by exhaustion. Purely client-side; no contract change.

### 2. Proactive renewal (preferred first step)

Extend the same session key rather than rotating to a new one:

- Add `Hub.refillSession(address sessionKey, uint256 addedCap, uint64 newExpiry)`, owner-only.
- When the client detects cap or time falling below a threshold, surface a toast: `세션 잔량 0.01 ETH — 연장하시겠습니까? [+0.05 ETH]`.
- Accepting produces **one** main-wallet signature. The session key address, its gas balance, and its in-memory state all persist, so gameplay can continue without a gap.

This is the smallest contract surface that unlocks a genuinely smooth experience.

### 3. Auto-extend (long-term)

Once a Paymaster predeploy and EIP-7702 delegation land, a player can pre-authorize a policy like "top up to 0.1 ETH whenever remaining cap dips below 0.02 ETH, up to a per-day ceiling." Renewal then requires zero interaction; exhaustion becomes invisible.

## Implementation checklist

- [ ] Contract: add `refillSession` (and corresponding SessionKeyManager method to mutate cap/expiry) with tests.
- [ ] Contract: clarify ordering — should `refillSession` also be callable when the session has already expired? (Design call; probably yes, with a fresh expiry.)
- [ ] Browser demo: cap meter + expiry countdown in Session panel.
- [ ] Browser demo: proactive renewal toast + one-click extension flow.
- [ ] Docs: update `docs/session-accounts.md` §4 lifecycle with the renewal path.
- [ ] Design: decide threshold policy (percentage of cap, absolute wei, time-based) and whether it is client-only or surfaced in Scope.

## Open design questions

- Should `refillSession` be atomic with a deposit (`depositAndRefill` analog to `depositAndRegister`)? Probably yes for UX parity.
- Do we allow the session key itself to initiate a refill request that the wallet then approves, similar to how ERC-4337 relayers sponsor bundles? Probably no for Phase 1 — keep the refill on the owner path.
- Does refill reset the nonce counter, or continue from the current one? Continue.
- Paymaster integration: when Phase 3 lands, the auto-extend path should reuse the same `refillSession` entry point, not introduce a parallel mechanism.

## Acceptance

A player can run a 30-minute session in the browser demo with a small initial cap and never see the flow stop, because renewal prompts land before exhaustion and a single signature extends the active session in place.
