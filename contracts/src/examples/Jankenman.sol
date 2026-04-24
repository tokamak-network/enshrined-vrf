// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title Jankenman
/// @notice On-chain rock-paper-scissors + roulette on native ETH, designed as
///         a showcase for two L2 primitives at once:
///
///          (1) Enshrined VRF — every round's randomness comes from a single
///              `VRF.getRandomness()` call, bound to the block.
///          (2) Session keys (AA-style UX) — a player deposits once with
///              MetaMask, which funds their in-contract `credits` balance AND
///              authorises a throw-away browser-held EOA to call `playFor`
///              on their behalf. Subsequent rounds settle with zero wallet
///              popups until the session expires or the player withdraws.
///
///         Game math per round (same as before):
///           1/3 draw  → bet refunded to credits
///           1/3 lose  → bet moved credits → lpAssets
///           1/3 win   → roulette on {1,2,4,7,20}× with weights
///                       {70,18,8,3,1}% — E[M|win] ≈ 1.79 ⇒ EV(player)=-7%
contract Jankenman {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    uint256 public constant MIN_BET         = 1e15;   // 0.001 ETH
    uint256 public constant MAX_PAYOUT_BPS  = 1000;   // single round ≤ 10% of pool

    // ─── LP pool ─────────────────────────────────────────────────
    uint256 public lpAssets;
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    // ─── Player credits (betting balance, kept separate from LP) ─
    /// @dev Invariant: sum(credits) + lpAssets == address(this).balance
    mapping(address => uint256) public credits;

    // ─── Session key auth ────────────────────────────────────────
    /// @dev sessionKey[owner][key] = unix timestamp until which the key may
    ///      call `playFor` on behalf of owner. 0 means revoked / never set.
    mapping(address => mapping(address => uint64)) public sessionKey;

    error BadHand();
    error BetTooSmall();
    error PoolTooShallow();
    error ZeroAmount();
    error NoShares();
    error NoCredits();
    error NotAuthorized();
    error SessionExpired();
    error GasFundExceedsValue();
    error TransferFailed();

    event LPDeposited   (address indexed lp, uint256 amount, uint256 sharesMinted, uint256 totalShares, uint256 lpAssets);
    event LPWithdrawn   (address indexed lp, uint256 sharesBurned, uint256 amount, uint256 totalShares, uint256 lpAssets);
    event Deposited     (address indexed player, uint256 amount, uint256 credits);
    event Withdrawn     (address indexed player, uint256 amount);
    event SessionStarted(address indexed owner, address indexed key, uint64 validUntil, uint256 deposit, uint256 gasFund);
    event SessionRevoked(address indexed owner, address indexed key);
    event Played(
        address indexed player,
        address          viaKey,       // session key that actually sent the tx (0 when owner plays directly)
        uint8            playerHand,
        uint8            houseHand,
        uint8            outcome,      // 0 lose · 1 draw · 2 win
        uint8            multiplier,
        uint256          bet,
        uint256          payout,
        uint256          randomness
    );

    // ── LP side ─────────────────────────────────────────────────
    function sharePrice() external view returns (uint256) {
        if (totalShares == 0) return 1 ether;
        return (lpAssets * 1 ether) / totalShares;
    }
    function previewDeposit(uint256 amount) external view returns (uint256) {
        if (totalShares == 0 || lpAssets == 0) return amount;
        return (amount * totalShares) / lpAssets;
    }
    function previewWithdraw(uint256 shares) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (shares * lpAssets) / totalShares;
    }

    function depositLP() external payable {
        if (msg.value == 0) revert ZeroAmount();
        uint256 minted = (totalShares == 0 || lpAssets == 0)
            ? msg.value
            : (msg.value * totalShares) / lpAssets;
        unchecked {
            sharesOf[msg.sender] += minted;
            totalShares          += minted;
            lpAssets             += msg.value;
        }
        emit LPDeposited(msg.sender, msg.value, minted, totalShares, lpAssets);
    }

    function withdrawLP(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        uint256 bal = sharesOf[msg.sender];
        if (bal < shares) revert NoShares();
        uint256 amount = (shares * lpAssets) / totalShares;
        unchecked {
            sharesOf[msg.sender] = bal - shares;
            totalShares         -= shares;
            lpAssets            -= amount;
        }
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit LPWithdrawn(msg.sender, shares, amount, totalShares, lpAssets);
    }

    // ── Player balance ───────────────────────────────────────────
    /// @notice Top up credits without touching session state.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        unchecked { credits[msg.sender] += msg.value; }
        emit Deposited(msg.sender, msg.value, credits[msg.sender]);
    }

    /// @notice Pull the player's entire credit balance back to their wallet.
    function withdraw() external {
        uint256 c = credits[msg.sender];
        if (c == 0) revert NoCredits();
        credits[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: c}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, c);
    }

    // ── Session key lifecycle ────────────────────────────────────
    /// @notice Onboard with a single transaction: top up credits AND authorise
    ///         a browser-held session key to play on the player's behalf AND
    ///         fund that key with enough ETH to cover future gas.
    /// @param key        EOA generated and held in the player's browser.
    /// @param validUntil Unix timestamp (seconds) — key expires after this.
    /// @param gasFund    Portion of msg.value forwarded to `key` for gas; the
    ///                   remainder becomes the player's betting credits.
    function startSession(address key, uint64 validUntil, uint256 gasFund) external payable {
        if (key == address(0))          revert NotAuthorized();
        if (validUntil <= block.timestamp) revert SessionExpired();
        if (gasFund > msg.value)        revert GasFundExceedsValue();

        sessionKey[msg.sender][key] = validUntil;

        uint256 depositAmt = msg.value - gasFund;
        if (depositAmt > 0) {
            unchecked { credits[msg.sender] += depositAmt; }
        }
        if (gasFund > 0) {
            (bool ok, ) = key.call{value: gasFund}("");
            if (!ok) revert TransferFailed();
        }
        emit SessionStarted(msg.sender, key, validUntil, depositAmt, gasFund);
    }

    /// @notice Extend / re-authorise an existing session key without moving funds.
    function setSessionKey(address key, uint64 validUntil) external {
        if (key == address(0)) revert NotAuthorized();
        sessionKey[msg.sender][key] = validUntil;
        emit SessionStarted(msg.sender, key, validUntil, 0, 0);
    }

    /// @notice Revoke a session key immediately.
    function revokeSession(address key) external {
        sessionKey[msg.sender][key] = 0;
        emit SessionRevoked(msg.sender, key);
    }

    // ── Game ─────────────────────────────────────────────────────
    /// @notice Direct play — owner signs each round.
    function play(uint8 hand, uint256 bet)
        external
        returns (uint8 houseHand, uint8 outcome, uint8 multiplier, uint256 payout, uint256 randomness)
    {
        return _play(msg.sender, address(0), hand, bet);
    }

    /// @notice Session-key play — called by an authorised key on behalf of
    ///         `owner`. Zero-signature UX during a live session.
    function playFor(address owner, uint8 hand, uint256 bet)
        external
        returns (uint8 houseHand, uint8 outcome, uint8 multiplier, uint256 payout, uint256 randomness)
    {
        uint64 expiry = sessionKey[owner][msg.sender];
        if (expiry == 0)              revert NotAuthorized();
        if (expiry <= block.timestamp) revert SessionExpired();
        return _play(owner, msg.sender, hand, bet);
    }

    function _play(address player, address viaKey, uint8 hand, uint256 bet)
        internal
        returns (uint8 houseHand, uint8 outcome, uint8 multiplier, uint256 payout, uint256 randomness)
    {
        if (hand > 2)                 revert BadHand();
        if (bet < MIN_BET)             revert BetTooSmall();
        if (credits[player] < bet)     revert NoCredits();
        // Cap worst-case payout at 10% of current pool to protect LPs.
        if (bet * 20 * 10_000 > lpAssets * MAX_PAYOUT_BPS) revert PoolTooShallow();

        randomness = VRF.getRandomness();
        houseHand = uint8(randomness % 3);

        if (hand == houseHand) {
            // Draw — bet never leaves credits.
            emit Played(player, viaKey, hand, houseHand, 1, 0, bet, 0, randomness);
            return (houseHand, 1, 0, 0, randomness);
        }

        // Rock(0)→Scissors(2), Paper(1)→Rock(0), Scissors(2)→Paper(1)
        bool playerWins = uint8((hand + 2) % 3) == houseHand;
        if (!playerWins) {
            // Lose — move bet from credits into the LP pool.
            unchecked {
                credits[player] -= bet;
                lpAssets        += bet;
            }
            emit Played(player, viaKey, hand, houseHand, 0, 0, bet, 0, randomness);
            return (houseHand, 0, 0, 0, randomness);
        }

        // Win — roll the roulette. Weights: 70/18/8/3/1 on {1,2,4,7,20}.
        uint256 r = uint256(keccak256(abi.encodePacked(randomness, uint8(1)))) % 100;
        if      (r < 70) multiplier = 1;
        else if (r < 88) multiplier = 2;
        else if (r < 96) multiplier = 4;
        else if (r < 99) multiplier = 7;
        else             multiplier = 20;

        payout = bet * multiplier;
        unchecked {
            credits[player] -= bet;       // debit the bet
            credits[player] += payout;    // credit the full payout back
            if (payout > bet) lpAssets -= (payout - bet);
            // multiplier < 1 not possible with this table
        }
        emit Played(player, viaKey, hand, houseHand, 2, multiplier, bet, payout, randomness);
    }

    // Accept bare ETH to seed the pool (no shares minted — counts as a donation).
    receive() external payable {
        unchecked { lpAssets += msg.value; }
    }
}
