// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "../interfaces/IEnshrainedVRF.sol";

/// @title RandomGenerator
/// @notice Minimal example that directly returns VRF randomness values.
contract RandomGenerator {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    event RandomGenerated(address indexed caller, uint256 value);

    /// @notice Returns a single random uint256.
    function random() external returns (uint256 value) {
        value = VRF.getRandomness();
        emit RandomGenerated(msg.sender, value);
    }

    /// @notice Returns a random number within [0, max).
    function randomInRange(uint256 max) external returns (uint256 value) {
        require(max > 0, "max must be > 0");
        value = VRF.getRandomness() % max;
        emit RandomGenerated(msg.sender, value);
    }

    /// @notice Returns multiple random values in a single transaction.
    function randomBatch(uint256 count) external returns (uint256[] memory values) {
        values = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            values[i] = VRF.getRandomness();
            emit RandomGenerated(msg.sender, values[i]);
        }
    }
}
