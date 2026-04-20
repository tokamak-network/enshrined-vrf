// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title GameRegistry
/// @notice Whitelist of contracts recognized as "games" on the L2.
///         Session keys may only call contracts registered here.
///         Designed to be a predeploy (address TBD).
contract GameRegistry {
    mapping(address => bool) private _registered;
    mapping(address => address) private _owner;

    event GameRegistered(address indexed game, address indexed registrar);
    event GameDeregistered(address indexed game, address indexed caller);

    error NotRegistered();
    error AlreadyRegistered();
    error NotOwner();

    /// @notice Register the caller as a game. Intended to be called by the
    ///         game contract itself from its constructor, so registration
    ///         authority cannot be spoofed by an EOA.
    function register() external {
        if (_registered[msg.sender]) revert AlreadyRegistered();
        _registered[msg.sender] = true;
        _owner[msg.sender] = tx.origin;
        emit GameRegistered(msg.sender, tx.origin);
    }

    /// @notice Deregister a game. Only the original registrar (tx.origin at
    ///         register time) may deregister.
    function deregister(address game) external {
        if (!_registered[game]) revert NotRegistered();
        if (_owner[game] != msg.sender) revert NotOwner();
        _registered[game] = false;
        emit GameDeregistered(game, msg.sender);
    }

    function isRegistered(address game) external view returns (bool) {
        return _registered[game];
    }

    function ownerOf(address game) external view returns (address) {
        return _owner[game];
    }
}
