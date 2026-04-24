// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title Lottery
/// @notice Open-entry raffle settled with one VRF call. Anyone enters during
///         a round; once at least one player has entered, anyone can call
///         draw() to pick a single winner uniformly at random. Multiple rounds
///         can run back-to-back — state is cleared after each draw.
contract Lottery {
    IEnshrainedVRF public constant VRF =
        IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    uint256 public round;
    address[] private _entries;
    mapping(uint256 => mapping(address => bool)) private _entered;

    error AlreadyEntered();
    error NoEntries();

    event Entered(uint256 indexed round, address indexed player, uint256 entryCount);
    event Drawn(uint256 indexed round, address indexed winner, uint256 entryCount, uint256 randomness);

    function enter() external {
        if (_entered[round][msg.sender]) revert AlreadyEntered();
        _entered[round][msg.sender] = true;
        _entries.push(msg.sender);
        emit Entered(round, msg.sender, _entries.length);
    }

    function draw() external returns (address winner) {
        uint256 n = _entries.length;
        if (n == 0) revert NoEntries();
        uint256 r = VRF.getRandomness();
        winner = _entries[r % n];
        emit Drawn(round, winner, n, r);

        // Reset for next round.
        round += 1;
        delete _entries;
    }

    function entryCount() external view returns (uint256) { return _entries.length; }
    function entryAt(uint256 i) external view returns (address) { return _entries[i]; }
    function hasEntered(address p) external view returns (bool) { return _entered[round][p]; }
}
