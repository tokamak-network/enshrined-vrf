// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SessionKeyManager} from "./SessionKeyManager.sol";
import {GameRegistry} from "./GameRegistry.sol";

/// @title GameHubAccount
/// @notice Per-user smart account. Owner (EOA) retains full authority;
///         session keys may call registered games within their scope.
///         Holds per-game balance slots.
contract GameHubAccount {
    address public immutable owner;
    address public immutable factory;
    SessionKeyManager public immutable sessionKeys;
    GameRegistry public immutable registry;

    /// @notice Per-game balance slots. Funds are earmarked for a specific game.
    mapping(address game => uint256) public balances;

    /// @notice Monotonic nonce for session-key-signed calls.
    mapping(address sessionKey => uint256) public sessionNonce;

    event Deposited(address indexed game, uint256 amount);
    event Withdrawn(address indexed game, uint256 amount, address indexed to);
    event SessionExecuted(address indexed sessionKey, address indexed game, bytes4 selector, uint256 value);

    error NotOwner();
    error GameNotRegistered();
    error InsufficientBalance();
    error InvalidSignature();
    error Unauthorized();
    error CallFailed(bytes reason);
    error BadNonce();

    constructor(address owner_, SessionKeyManager skm, GameRegistry reg, address factory_) {
        owner = owner_;
        sessionKeys = skm;
        registry = reg;
        factory = factory_;
    }

    modifier onlyOwnerOrFactory() {
        if (msg.sender != owner && msg.sender != factory) revert NotOwner();
        _;
    }

    receive() external payable {}

    /// @notice Deposit ETH into a game-specific slot. Callable by owner only.
    function deposit(address game) external payable onlyOwnerOrFactory {
        if (!registry.isRegistered(game)) revert GameNotRegistered();
        balances[game] += msg.value;
        emit Deposited(game, msg.value);
    }

    /// @notice Register a session key for a game. Callable by owner or factory.
    function registerSession(address sessionKey, SessionKeyManager.Scope calldata scope)
        external
        onlyOwnerOrFactory
    {
        if (!registry.isRegistered(scope.gameAddr)) revert GameNotRegistered();
        sessionKeys.register(sessionKey, scope);
    }

    /// @notice Revoke a session key. Callable by owner only.
    function revokeSession(address sessionKey) external {
        if (msg.sender != owner) revert NotOwner();
        sessionKeys.revoke(sessionKey);
    }

    /// @notice Top up an existing session key: optional game-slot deposit, cap increase,
    ///         and/or expiry extension. Single owner signature extends an active session
    ///         without rotating keys.
    function refillSession(
        address sessionKey,
        address game,
        uint256 addedCap,
        uint64 newExpiry
    ) external payable onlyOwnerOrFactory {
        if (msg.value > 0) {
            if (!registry.isRegistered(game)) revert GameNotRegistered();
            balances[game] += msg.value;
            emit Deposited(game, msg.value);
        }
        sessionKeys.refill(sessionKey, addedCap, newExpiry);
    }

    /// @notice Withdraw from a game slot back to the caller or a recipient.
    function withdraw(address game, uint256 amount, address payable to) external {
        if (msg.sender != owner) revert NotOwner();
        if (balances[game] < amount) revert InsufficientBalance();
        balances[game] -= amount;
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert CallFailed("");
        emit Withdrawn(game, amount, to);
    }

    /// @notice Execute a call directly (owner-signed path).
    function executeAsOwner(address game, uint256 value, bytes calldata data) external returns (bytes memory) {
        if (msg.sender != owner) revert NotOwner();
        return _call(game, value, data);
    }

    /// @notice Execute a call on behalf of a session key. Anyone may submit
    ///         this transaction (including a relayer) as long as the signature
    ///         and scope validate.
    /// @param  sessionKey  The session key signer.
    /// @param  game        Target game contract.
    /// @param  value       Wei to forward from balances[game].
    /// @param  data        Calldata (must include selector).
    /// @param  nonce       Expected sessionNonce[sessionKey].
    /// @param  signature   65-byte ECDSA signature over the digest below.
    function executeAsSession(
        address sessionKey,
        address game,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        bytes calldata signature
    ) external returns (bytes memory) {
        if (nonce != sessionNonce[sessionKey]) revert BadNonce();

        bytes32 digest = _digest(sessionKey, game, value, data, nonce);
        address recovered = _recover(digest, signature);
        if (recovered != sessionKey) revert InvalidSignature();

        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        if (!sessionKeys.canCall(address(this), sessionKey, game, selector, value)) {
            revert Unauthorized();
        }
        if (balances[game] < value) revert InsufficientBalance();

        sessionNonce[sessionKey] = nonce + 1;
        balances[game] -= value;
        if (value > 0) sessionKeys.consume(sessionKey, value);

        emit SessionExecuted(sessionKey, game, selector, value);
        return _call(game, value, data);
    }

    // ──────────────────────────────────────────────────────────────
    // Internals
    // ──────────────────────────────────────────────────────────────

    function _call(address target, uint256 value, bytes calldata data) internal returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) revert CallFailed(ret);
        return ret;
    }

    function _digest(
        address sessionKey,
        address game,
        uint256 value,
        bytes calldata data,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                address(this),
                block.chainid,
                sessionKey,
                game,
                value,
                keccak256(data),
                nonce
            )
        );
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
    }

    function _recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (v < 27) v += 27;
        return ecrecover(digest, v, r, s);
    }
}
