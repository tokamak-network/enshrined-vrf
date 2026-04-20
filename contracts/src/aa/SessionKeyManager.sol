// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SessionKeyManager
/// @notice Tracks scoped session keys for GameHub accounts.
///         Only the Hub itself may register/revoke keys for its own address.
///         Validation is pure view — callers (Hubs) enforce the result.
///         Designed to be a predeploy (address TBD).
contract SessionKeyManager {
    struct Scope {
        address gameAddr;      // target game contract
        uint256 spendingCap;   // remaining value (wei) the key may spend
        uint64  expiry;        // unix timestamp; 0 = no expiry
        bytes4[] selectors;    // allowed function selectors; empty = any
    }

    mapping(address hub => mapping(address key => Scope)) private _scopes;
    mapping(address hub => mapping(address key => bool)) private _active;

    event SessionRegistered(
        address indexed hub,
        address indexed sessionKey,
        address indexed gameAddr,
        uint256 cap,
        uint64 expiry
    );
    event SessionRevoked(address indexed hub, address indexed sessionKey);
    event CapConsumed(address indexed hub, address indexed sessionKey, uint256 amount, uint256 remaining);
    event SessionRefilled(
        address indexed hub,
        address indexed sessionKey,
        uint256 addedCap,
        uint64 newExpiry
    );

    error AlreadyActive();
    error NotActive();
    error InvalidGame();
    error InvalidExpiry();
    error NotHub();

    /// @notice Register a session key for the calling Hub.
    /// @dev    msg.sender is the Hub. Only the Hub can register keys for itself.
    function register(address sessionKey, Scope calldata scope) external {
        if (_active[msg.sender][sessionKey]) revert AlreadyActive();
        if (scope.gameAddr == address(0)) revert InvalidGame();
        if (scope.expiry != 0 && scope.expiry <= block.timestamp) revert InvalidExpiry();

        _scopes[msg.sender][sessionKey] = scope;
        _active[msg.sender][sessionKey] = true;

        emit SessionRegistered(msg.sender, sessionKey, scope.gameAddr, scope.spendingCap, scope.expiry);
    }

    /// @notice Revoke a session key. Callable by the Hub that owns it.
    function revoke(address sessionKey) external {
        if (!_active[msg.sender][sessionKey]) revert NotActive();
        _active[msg.sender][sessionKey] = false;
        emit SessionRevoked(msg.sender, sessionKey);
    }

    /// @notice Top up an active session key's remaining cap and/or extend its expiry.
    /// @dev    Works on sessions whose expiry has passed (revives gameplay), but NOT on
    ///         revoked sessions — those must be re-registered from scratch.
    /// @param  sessionKey  The key to refill.
    /// @param  addedCap    Wei to add to `spendingCap`. May be zero if only extending expiry.
    /// @param  newExpiry   New absolute unix timestamp. 0 leaves expiry unchanged;
    ///                     any non-zero value must be in the future.
    function refill(address sessionKey, uint256 addedCap, uint64 newExpiry) external {
        if (!_active[msg.sender][sessionKey]) revert NotActive();
        Scope storage s = _scopes[msg.sender][sessionKey];
        s.spendingCap += addedCap;
        if (newExpiry != 0) {
            if (newExpiry <= block.timestamp) revert InvalidExpiry();
            s.expiry = newExpiry;
        }
        emit SessionRefilled(msg.sender, sessionKey, addedCap, s.expiry);
    }

    /// @notice Check whether a session key is authorized for a given call.
    ///         Pure view — does not mutate cap. Hub must call consume() after execution.
    function canCall(
        address hub,
        address sessionKey,
        address gameAddr,
        bytes4 selector,
        uint256 value
    ) external view returns (bool) {
        if (!_active[hub][sessionKey]) return false;
        Scope storage s = _scopes[hub][sessionKey];
        if (s.gameAddr != gameAddr) return false;
        if (s.expiry != 0 && s.expiry <= block.timestamp) return false;
        if (value > s.spendingCap) return false;
        if (s.selectors.length > 0) {
            bool match_;
            for (uint256 i; i < s.selectors.length; ++i) {
                if (s.selectors[i] == selector) { match_ = true; break; }
            }
            if (!match_) return false;
        }
        return true;
    }

    /// @notice Deduct spent value from the session key's remaining cap.
    /// @dev    Called by the Hub after a successful session-key execution.
    function consume(address sessionKey, uint256 amount) external {
        if (!_active[msg.sender][sessionKey]) revert NotActive();
        Scope storage s = _scopes[msg.sender][sessionKey];
        s.spendingCap -= amount; // underflow reverts (≥0.8)
        emit CapConsumed(msg.sender, sessionKey, amount, s.spendingCap);
    }

    function scopeOf(address hub, address sessionKey) external view returns (Scope memory) {
        return _scopes[hub][sessionKey];
    }

    function isActive(address hub, address sessionKey) external view returns (bool) {
        return _active[hub][sessionKey];
    }
}
