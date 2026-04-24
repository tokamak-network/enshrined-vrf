// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title Plinko
/// @notice Drop a ball through 12 peg rows. Each row flips the ball left/right
///         based on one bit derived from the VRF value — final slot = popcount
///         of the 12-bit path. 13 slots total (0..12), binomially distributed.
contract Plinko {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    uint8 public constant ROWS = 12;

    event Dropped(address indexed player, uint16 path, uint8 slot, uint256 randomness);

    function drop() external returns (uint16 path, uint8 slot) {
        uint256 r = VRF.getRandomness();
        // Use low 12 bits as the path — 1 = right, 0 = left.
        path = uint16(r & 0x0FFF);
        // Slot = number of right-flips = popcount(path).
        uint16 p = path;
        uint8 count;
        unchecked {
            while (p != 0) { count += uint8(p & 1); p >>= 1; }
        }
        slot = count;
        emit Dropped(msg.sender, path, slot, r);
    }
}
