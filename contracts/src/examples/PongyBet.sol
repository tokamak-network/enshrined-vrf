// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @title PongyBet
/// @notice On-chain 짱깸뽀 (rock-paper-scissors + roulette) settled in USDC.
///         One VRF call per round, one SSTORE for balance updates.
contract PongyBet {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);
    IERC20 public immutable USDC;

    /// @dev 1 USDC (6 decimals) — bet per round.
    uint256 public constant BET = 1e6;

    /// @dev Packed per-player balance: credits + medals share one storage slot.
    ///      uint128 each is enough for any realistic USDC amount.
    struct Balance { uint128 credits; uint128 medals; }
    mapping(address => Balance) private _bal;

    // Custom errors (cheaper revert than require strings).
    error ZeroAmount();
    error TransferFailed();
    error BadHand();
    error InsufficientCredits();
    error NoMedals();

    event Deposited(address indexed player, uint256 amount);
    event Withdrawn(address indexed player, uint256 amount);
    event Played(
        address indexed player,
        uint8 playerHand,
        uint8 machineHand,
        uint8 outcome,      // 0=lose 1=draw 2=win
        uint8 multiplier,   // 0 | 1 | 2 | 4 | 7 | 20
        uint256 payout,
        uint256 randomness
    );

    constructor(address usdc) { USDC = IERC20(usdc); }

    // --- views (match frontend GameEngine.getBalance shape) ---
    function credits(address p) external view returns (uint256) { return _bal[p].credits; }
    function medals(address p) external view returns (uint256) { return _bal[p].medals; }
    function balanceOf(address p) external view returns (uint256, uint256) {
        Balance memory b = _bal[p];
        return (b.credits, b.medals);
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (!USDC.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        unchecked { _bal[msg.sender].credits += uint128(amount); }
        emit Deposited(msg.sender, amount);
    }

    /// @notice Play a round. Single tx: debit → VRF → judge → roulette → settle.
    function play(uint8 playerHand)
        external
        returns (
            uint8 machineHand,
            uint8 outcome,
            uint8 multiplier,
            uint256 payout,
            uint256 randomness
        )
    {
        if (playerHand > 2) revert BadHand();
        Balance memory b = _bal[msg.sender];
        if (b.credits < BET) revert InsufficientCredits();

        randomness = VRF.getRandomness();
        machineHand = uint8(randomness % 3);

        if (playerHand == machineHand) {
            // Draw: no bet debited, nothing to write. Emit only.
            outcome = 1;
            emit Played(msg.sender, playerHand, machineHand, 1, 0, 0, randomness);
            return (machineHand, 1, 0, 0, randomness);
        }

        unchecked { b.credits -= uint128(BET); }

        // Win iff (playerHand + 1) % 3 == machineHand.
        // rock(0)>scissors(1), scissors(1)>paper(2), paper(2)>rock(0)
        if (uint8((playerHand + 1) % 3) == machineHand) {
            outcome = 2;
            // Second random draw: hash the VRF output with a domain separator.
            // Cheaper than a second VRF call and still bound to that block.
            uint256 r2 = uint256(keccak256(abi.encodePacked(randomness, uint8(1)))) % 100;
            if (r2 < 50)       multiplier = 1;
            else if (r2 < 75)  multiplier = 2;
            else if (r2 < 90)  multiplier = 4;
            else if (r2 < 98)  multiplier = 7;
            else               multiplier = 20;
            payout = BET * multiplier;
            unchecked { b.medals += uint128(payout); }
        }
        // outcome stays 0 (lose) and payout 0 by default — no branch needed.

        _bal[msg.sender] = b; // single SSTORE for both fields
        emit Played(msg.sender, playerHand, machineHand, outcome, multiplier, payout, randomness);
    }

    function withdraw() external {
        uint256 m = _bal[msg.sender].medals;
        if (m == 0) revert NoMedals();
        _bal[msg.sender].medals = 0;
        if (!USDC.transfer(msg.sender, m)) revert TransferFailed();
        emit Withdrawn(msg.sender, m);
    }
}
