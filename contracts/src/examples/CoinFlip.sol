// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title CoinFlip
/// @notice Example contract demonstrating Enshrined VRF usage.
///         Each flip() call consumes one VRF randomness and returns heads or tails.
contract CoinFlip {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    event Flipped(address indexed player, bool heads, uint256 randomness);

    /// @notice Flip a coin using on-chain verifiable randomness.
    /// @return heads True if heads (even), false if tails (odd).
    function flip() external returns (bool heads) {
        uint256 randomness = VRF.getRandomness();
        heads = (randomness % 2 == 0);
        emit Flipped(msg.sender, heads, randomness);
    }

    /// @notice Roll a dice (1-6) using on-chain verifiable randomness.
    /// @return result A number between 1 and 6.
    function rollDice() external returns (uint8 result) {
        uint256 randomness = VRF.getRandomness();
        result = uint8((randomness % 6) + 1);
    }
}
