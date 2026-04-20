// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {GameHubAccount} from "./GameHubAccount.sol";
import {SessionKeyManager} from "./SessionKeyManager.sol";
import {GameRegistry} from "./GameRegistry.sol";

/// @title GameHubFactory
/// @notice Deterministically deploys one GameHubAccount per EOA via CREATE2.
///         Also provides an atomic deposit + session-registration flow so
///         first-time users complete onboarding in a single signature.
///         Designed to be a predeploy (address TBD).
contract GameHubFactory {
    SessionKeyManager public immutable sessionKeys;
    GameRegistry public immutable registry;

    event HubDeployed(address indexed owner, address hub);

    constructor(SessionKeyManager skm, GameRegistry reg) {
        sessionKeys = skm;
        registry = reg;
    }

    /// @notice Deterministic hub address for a given owner.
    function hubOf(address owner) public view returns (address) {
        bytes32 salt = bytes32(uint256(uint160(owner)));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(GameHubAccount).creationCode,
                abi.encode(owner, sessionKeys, registry, address(this))
            )
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)
        ))));
    }

    /// @notice Deploy Hub if missing, then deposit + register a session key
    ///         in a single call. Intended as the one-signature onboarding tx.
    function depositAndRegister(
        address sessionKey,
        SessionKeyManager.Scope calldata scope
    ) external payable returns (address hubAddr) {
        hubAddr = hubOf(msg.sender);
        if (hubAddr.code.length == 0) {
            bytes32 salt = bytes32(uint256(uint160(msg.sender)));
            GameHubAccount deployed = new GameHubAccount{salt: salt}(msg.sender, sessionKeys, registry, address(this));
            require(address(deployed) == hubAddr, "factory/address-mismatch");
            emit HubDeployed(msg.sender, hubAddr);
        }

        // Forward deposit and session registration through the Hub so that
        // the Hub itself is the caller into SessionKeyManager, keeping the
        // "only Hub may register for itself" invariant.
        (bool okDep, ) = hubAddr.call{value: msg.value}(
            abi.encodeCall(GameHubAccount.deposit, (scope.gameAddr))
        );
        require(okDep, "factory/deposit-failed");

        (bool okReg, ) = hubAddr.call(
            abi.encodeCall(GameHubAccount.registerSession, (sessionKey, scope))
        );
        require(okReg, "factory/register-failed");
    }

    /// @notice Deposit + refill an existing session in a single signature.
    /// @dev    msg.value is added to balances[game]; addedCap and newExpiry update
    ///         the session's on-chain scope. Requires the Hub to already exist and
    ///         the session to be active (not revoked).
    function depositAndRefill(
        address sessionKey,
        address game,
        uint256 addedCap,
        uint64 newExpiry
    ) external payable returns (address hubAddr) {
        hubAddr = hubOf(msg.sender);
        require(hubAddr.code.length > 0, "factory/hub-missing");

        (bool ok, ) = hubAddr.call{value: msg.value}(
            abi.encodeCall(GameHubAccount.refillSession, (sessionKey, game, addedCap, newExpiry))
        );
        require(ok, "factory/refill-failed");
    }
}
