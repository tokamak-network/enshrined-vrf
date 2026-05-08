// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title TRHGameRandomness
/// @notice Minimal adapter for games deployed on a TRH/Thanos chain with
///         Enshrained VRF enabled. Pass address(0) in production to use the
///         fixed predeploy; pass a mock address in tests.
abstract contract TRHGameRandomness {
    address public constant ENSHRINED_VRF_PREDEPLOY = 0x42000000000000000000000000000000000000f0;

    IEnshrainedVRF public immutable vrf;

    error InvalidRandomRange();

    constructor(address vrfOverride) {
        vrf = IEnshrainedVRF(vrfOverride == address(0) ? ENSHRINED_VRF_PREDEPLOY : vrfOverride);
    }

    function _randomBelow(uint256 upperExclusive) internal returns (uint256) {
        if (upperExclusive == 0) revert InvalidRandomRange();
        return vrf.getRandomness() % upperExclusive;
    }
}

/// @title TRHDiceGame
/// @notice Small game-facing example that consumes one Enshrained VRF value
///         per roll and supports test injection through the constructor.
contract TRHDiceGame is TRHGameRandomness {
    event Rolled(address indexed player, uint8 sides, uint8 result);

    error InvalidDiceSides();

    constructor(address vrfOverride) TRHGameRandomness(vrfOverride) {}

    function roll(uint8 sides) external returns (uint8 result) {
        if (sides < 2) revert InvalidDiceSides();
        result = uint8(_randomBelow(sides) + 1);
        emit Rolled(msg.sender, sides, result);
    }
}
