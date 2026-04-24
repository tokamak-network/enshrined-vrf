// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {PongyBet} from "../src/examples/PongyBet.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/// @title DeployPongyBet
/// @notice Deploys PongyBet. If `USDC` env var is not set, also deploys a
///         MockUSDC for local/devnet use and seeds the deployer with $1000.
///
/// Usage:
///   # With existing USDC on L2:
///   USDC=0x... forge script script/DeployPongyBet.s.sol \
///       --rpc-url $L2_RPC --broadcast --private-key $PK
///
///   # With MockUSDC (local devnet):
///   forge script script/DeployPongyBet.s.sol \
///       --rpc-url $L2_RPC --broadcast --private-key $PK
contract DeployPongyBet is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address usdc = vm.envOr("USDC", address(0));

        vm.startBroadcast(pk);

        if (usdc == address(0)) {
            MockUSDC mock = new MockUSDC();
            usdc = address(mock);
            // seed deployer with $1000 for demo sessions
            mock.mint(deployer, 1_000 * 10**6);
            console2.log("MockUSDC deployed at:", usdc);
            console2.log("Deployer seeded with 1000 USDC");
        } else {
            console2.log("Using existing USDC at:", usdc);
        }

        PongyBet game = new PongyBet(usdc);
        console2.log("PongyBet deployed at:", address(game));

        vm.stopBroadcast();

        // Summary block — copy-paste these addresses into the frontend config.
        console2.log("=== Frontend config ===");
        console2.log("gameAddress:", address(game));
        console2.log("usdcAddress:", usdc);
    }
}
