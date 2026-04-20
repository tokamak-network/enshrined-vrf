// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";
import {GameRegistry} from "../GameRegistry.sol";

/// @title CoinFlipGame
/// @notice Minimal VRF-backed coin flip. Each flip consumes BET and returns heads/tails.
///         Self-registers with GameRegistry so session keys may call it.
contract CoinFlipGame {
    IEnshrainedVRF public immutable vrf;
    uint256 public constant BET = 0.01 ether;

    event Flipped(address indexed player, bool heads, uint256 randomness);

    error WrongBet();

    constructor(GameRegistry registry, IEnshrainedVRF vrf_) {
        vrf = vrf_;
        registry.register();
    }

    function flip() external payable returns (bool heads) {
        if (msg.value != BET) revert WrongBet();
        uint256 r = vrf.getRandomness();
        heads = (r % 2 == 0);
        emit Flipped(msg.sender, heads, r);
    }
}
