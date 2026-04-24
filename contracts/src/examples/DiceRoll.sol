// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title DiceRoll
/// @notice Arcade demo — roll two six-sided dice with verifiable randomness.
///         Each roll consumes one VRF value; the two faces are derived via
///         keccak domain separation to stay in a single tx.
contract DiceRoll {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    event Rolled(address indexed player, uint8 d1, uint8 d2, uint8 total, uint256 randomness);

    function roll() external returns (uint8 d1, uint8 d2, uint8 total) {
        uint256 r = VRF.getRandomness();
        d1 = uint8((r % 6) + 1);
        d2 = uint8((uint256(keccak256(abi.encodePacked(r, uint8(1)))) % 6) + 1);
        total = d1 + d2;
        emit Rolled(msg.sender, d1, d2, total, r);
    }
}
