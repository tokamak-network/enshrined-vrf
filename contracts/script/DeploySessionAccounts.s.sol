// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {GameRegistry} from "../src/aa/GameRegistry.sol";
import {SessionKeyManager} from "../src/aa/SessionKeyManager.sol";
import {GameHubFactory} from "../src/aa/GameHubFactory.sol";
import {DrawGame} from "../src/aa/examples/DrawGame.sol";
import {CoinFlipGame} from "../src/aa/examples/CoinFlipGame.sol";
import {MockVRF} from "../src/mocks/MockVRF.sol";
import {IEnshrainedVRF} from "interfaces/L2/IEnshrainedVRF.sol";

/// @title DeploySessionAccounts
/// @notice Deploys the Phase 1 Session Accounts stack for the browser demo.
///         Uses MockVRF unless VRF env var is provided.
///
/// Usage:
///   PRIVATE_KEY=0x... forge script script/DeploySessionAccounts.s.sol \
///       --rpc-url $RPC --broadcast
contract DeploySessionAccounts is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vrfAddr = vm.envOr("VRF", address(0));

        vm.startBroadcast(pk);

        GameRegistry registry = new GameRegistry();
        SessionKeyManager skm = new SessionKeyManager();
        GameHubFactory factory = new GameHubFactory(skm, registry);

        if (vrfAddr == address(0)) {
            vrfAddr = address(new MockVRF());
            console2.log("MockVRF deployed at:", vrfAddr);
        } else {
            console2.log("Using existing VRF at:", vrfAddr);
        }

        DrawGame draw = new DrawGame(registry, IEnshrainedVRF(vrfAddr));
        CoinFlipGame coin = new CoinFlipGame(registry, IEnshrainedVRF(vrfAddr));

        vm.stopBroadcast();

        console2.log("=== Frontend config ===");
        console2.log("registry:", address(registry));
        console2.log("sessionKeys:", address(skm));
        console2.log("factory:", address(factory));
        console2.log("drawGame:", address(draw));
        console2.log("coinFlipGame:", address(coin));
        console2.log("vrf:", vrfAddr);
    }
}
