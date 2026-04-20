// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";
import {GameRegistry} from "../GameRegistry.sol";

/// @title DrawGame
/// @notice Minimal VRF-backed gacha: each draw consumes a bet and returns a
///         tier in [0, 99]. Self-registers with GameRegistry on deploy so
///         session keys may call it.
contract DrawGame {
    IEnshrainedVRF public immutable vrf;
    uint256 public constant BET = 0.01 ether;

    event Draw(address indexed player, uint256 tier, uint256 randomness);

    error WrongBet();

    constructor(GameRegistry registry, IEnshrainedVRF vrf_) {
        vrf = vrf_;
        registry.register();
    }

    function draw() external payable returns (uint256 tier) {
        if (msg.value != BET) revert WrongBet();
        uint256 r = vrf.getRandomness();
        tier = r % 100;
        emit Draw(msg.sender, tier, r);
    }
}
