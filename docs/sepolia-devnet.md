# Sepolia-Backed Local L2 Devnet

This runbook starts a local OP Stack L2 execution engine and sequencer while using Sepolia as L1. It is intended for Enshrined VRF development: the L2 chain runs locally, the L1 SystemConfig lives on Sepolia, and the local chain can consume randomness from the `EnshrainedVRF` predeploy.

The scripts refuse any L1 RPC whose chain ID is not `11155111`, so they will not deploy to Ethereum mainnet by accident. The prepare step does deploy L1 contracts and send a `SystemConfig.setVRFPublicKey(bytes)` transaction on Sepolia, so use a funded Sepolia key only.

## Prerequisites

- Go, Foundry (`forge`, `cast`), and `jq`
- A Sepolia execution RPC in `L1_RPC_URL`
- A funded Sepolia private key in `PRIVATE_KEY`
- Optional but recommended: a Sepolia beacon API in `L1_BEACON_URL`

## Configure

```bash
cp devnet/sepolia/.env.example devnet/sepolia/.env
$EDITOR devnet/sepolia/.env
```

You can also export the same variables in your shell instead of creating the
`.env` file. The scripts load `devnet/sepolia/.env` when it exists and then
fall back to the current environment.

The default `L2_CHAIN_ID=901005` is a private local chain ID. Change it if it conflicts with another local chain.

The default `VRF_SK` is development-only and is passed to op-node in `--sequencer.vrf-mode=local`. For TEE mode, set:

```bash
VRF_MODE=tee
VRF_TEE_ENDPOINT=localhost:50051
```

## Preflight

Run a non-destructive readiness check before deploying anything to Sepolia:

```bash
./scripts/devnet-sepolia-preflight.sh
```

This checks local tools, binary/artifact presence, `PRIVATE_KEY` parsing, the Sepolia chain-id guard for `L1_RPC_URL`, default VRF public-key derivation, and op-deployer cache/workdir behavior. It does not send transactions. Chain ID checks use raw JSON-RPC through `curl` first and fall back to `cast`.

## One-Command Flow

To run preflight, prepare, start, and randomness verification in order:

```bash
./scripts/devnet-sepolia-up.sh
```

Set `VERIFY_AFTER_START=0` to start the chain without running the consumer
verification step immediately.

## Prepare Sepolia State and Local Genesis

```bash
./scripts/devnet-sepolia-prepare.sh
```

This step:

- Builds `bin/geth`, `bin/op-node`, `bin/op-deployer`, and `bin/vrf-prove`
- Builds local contracts-bedrock artifacts with `forge build`
- Creates an op-deployer custom Sepolia intent with `l2GenesisEnshrainedVRFTimeOffset = 0`
- Applies the intent to Sepolia
- Renders `.devnet/sepolia/genesis.json`, `rollup.json`, `deploy-config.json`, and `l1-addresses.json`
- Stores op-deployer cache data under `.devnet/sepolia/op-deployer-cache`
- Initializes the local op-geth datadir
- Derives the VRF public key from `VRF_SK`
- Sends `SystemConfig.setVRFPublicKey(bytes)` on Sepolia unless it is already set
- Writes `.devnet/sepolia/devnet.json`

To reuse already-built binaries or artifacts:

```bash
BUILD_BINARIES=0 BUILD_CONTRACTS=0 ./scripts/devnet-sepolia-prepare.sh
```

## Start the Local L2

```bash
./scripts/devnet-sepolia-start.sh
```

Default local endpoints:

- L2 RPC: `http://127.0.0.1:9545`
- L2 WebSocket: `ws://127.0.0.1:9546`
- L2 engine auth RPC: `http://127.0.0.1:9551`
- op-node admin RPC: `http://127.0.0.1:7545`

RPC services bind to `127.0.0.1` by default. Override `L2_RPC_ADDR`,
`L2_WS_ADDR`, `L2_AUTHRPC_ADDR`, or `OP_NODE_RPC_ADDR` only when you
intentionally want to expose them beyond localhost. If you override ports, pass
the same variables to verification, for example
`L2_RPC_PORT=8545 ./scripts/devnet-sepolia-verify-random.sh`.

Logs are written to `.devnet/sepolia/logs/geth.log` and `.devnet/sepolia/logs/op-node.log`.

## Verify Randomness

```bash
./scripts/devnet-sepolia-verify-random.sh
```

The verification script checks:

- The local L2 RPC is serving the expected chain ID
- `EnshrainedVRF` has code at `0x42000000000000000000000000000000000000f0`
- `commitNonce()` advances above zero
- `sequencerPublicKey()` is set on L2 and matches the key registered on Sepolia
- `getRandomness()` returns a value
- A `CoinFlip` example contract can be deployed and can call `flip()`

For a lighter check without deploying the consumer contract:

```bash
VERIFY_CONSUMER=0 ./scripts/devnet-sepolia-verify-random.sh
```

Manual checks:

```bash
cast chain-id --rpc-url http://127.0.0.1:9545
cast call 0x42000000000000000000000000000000000000f0 "commitNonce()(uint256)" --rpc-url http://127.0.0.1:9545
cast call 0x42000000000000000000000000000000000000f0 "sequencerPublicKey()(bytes)" --rpc-url http://127.0.0.1:9545
cast call 0x42000000000000000000000000000000000000f0 "getRandomness()(uint256)" --rpc-url http://127.0.0.1:9545
```

## Stop

```bash
./scripts/devnet-sepolia-stop.sh
```

## Reset

To rebuild from scratch, stop the devnet and remove the local workdir:

```bash
./scripts/devnet-sepolia-stop.sh
rm -rf .devnet/sepolia
```

Then rerun prepare and start.

## Notes

- `L1_RPC_URL` must point to Sepolia. The prepare and start scripts exit if `cast chain-id` does not return `11155111`.
- The L2 chain is local and unsafe-sequenced. It is not a public testnet.
- If `sequencerPublicKey()` never becomes non-empty on L2, rebuild `bin/geth` from this repo and restart. The patched op-geth injects a system deposit that calls `EnshrainedVRF.setSequencerPublicKey(bytes)` using the public key derived from L1 SystemConfig.
- If `commitNonce()` does not advance, inspect `op-node.log` for VRF proof errors and `geth.log` for payload execution errors.
