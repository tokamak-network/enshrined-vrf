# Enshrined VRF Testing Guide

This guide lists the checks that cover the current Enshrined VRF OP Stack integration. For the Sepolia-backed local L2 runbook, see [sepolia-devnet.md](sepolia-devnet.md).

## Prerequisites

```bash
go version       # Go 1.24+
forge --version  # Foundry
cast --version
jq --version
```

## 1. Core Cryptography

Run from the repository root:

```bash
go test ./crypto/ecvrf/ -v
go test ./crypto/ecvrf/ -bench=. -benchmem
go test ./crypto/ecvrf/ -fuzz=FuzzProveVerify -fuzztime=30s
go test ./crypto/ecvrf/ -fuzz=FuzzVerifyRejectsRandom -fuzztime=30s
```

These tests cover ECVRF prove/verify round trips, proof rejection, determinism, and benchmark timing for the root library.

## 2. L2 and L1 Contracts

Run from the root `contracts` package:

```bash
cd contracts
forge test --match-contract EnshrainedVRFTest -v
forge test --match-contract VRFVerifierTest -v
```

`EnshrainedVRFTest` covers the L2 predeploy interface: `setSequencerPublicKey`, `commitRandomness`, `getRandomness`, `getResult`, `commitNonce`, and `callCounter`.

`VRFVerifierTest` covers the L1 dispute helper. The current helper verifies seed construction and proof structure / `proofToHash`; it is not the normal L2 commit path.

## 3. op-geth Integration

```bash
cd op-geth

go test ./crypto/ecvrf/ -v
go test ./core/vm/ -run ECVRF -v
go test ./beacon/engine/ -run VRF -v
go test ./miner/ -run 'VRF|PayloadIdIncludesVRFAttributes' -v
```

These checks cover:

- ECVRF verify precompile at `0x0101`
- Engine API VRF payload attribute JSON encoding as hex
- Payload ID separation when VRF attributes differ
- ABI encoding for `setSequencerPublicKey(bytes)` and `commitRandomness(uint256,bytes32,bytes32,bytes)`
- op-geth deposit construction for public-key sync and randomness commitment

## 4. optimism / op-node Integration

```bash
cd optimism

go test ./op-service/eth -run VRF -v
go test ./op-node/rollup/derive -run 'VRF|SystemConfig|PreparePayloadAttributes' -v
```

These checks cover:

- `eth.SystemConfig.VRFPublicKey` and VRF payload attributes encoding as hex
- parsing `SystemConfig` `ConfigUpdate(UpdateType.VRF_PUBLIC_KEY, data)` logs
- `ComputeVRFSeed(blockNumber, nonce)`
- local and TEE-backed `VRFProver` paths
- carrying VRF fields through singular/span batches
- restoring VRF fields into derived payload attributes

## 5. Sepolia-Backed Local L2 E2E

The Sepolia devnet scripts run a local L2 execution client and op-node sequencer while reading L1 state from Sepolia. The scripts refuse non-Sepolia L1 RPC endpoints.

```bash
cp devnet/sepolia/.env.example devnet/sepolia/.env
$EDITOR devnet/sepolia/.env

./scripts/devnet-sepolia-preflight.sh
./scripts/devnet-sepolia-prepare.sh
./scripts/devnet-sepolia-start.sh
./scripts/devnet-sepolia-verify-random.sh
```

The verification script checks:

- local L2 chain ID matches the configured `L2_CHAIN_ID`
- `EnshrainedVRF` has bytecode at `0x42000000000000000000000000000000000000f0`
- `commitNonce()` advances
- `sequencerPublicKey()` is set on L2 and matches Sepolia `SystemConfig.vrfPublicKey()`
- `getRandomness()` returns a value in a local L2 transaction
- a `CoinFlip` consumer contract can call `flip()`

For a lighter check:

```bash
VERIFY_CONSUMER=0 ./scripts/devnet-sepolia-verify-random.sh
```

## 6. Manual E2E Checks

Default Sepolia local L2 endpoint:

```bash
export L2_RPC_URL=http://127.0.0.1:9545
export VRF=0x42000000000000000000000000000000000000f0
```

Check the predeploy and public key:

```bash
cast code "$VRF" --rpc-url "$L2_RPC_URL"
cast call "$VRF" "sequencerPublicKey()(bytes)" --rpc-url "$L2_RPC_URL"
cast call "$VRF" "commitNonce()(uint256)" --rpc-url "$L2_RPC_URL"
```

Query a historical result:

```bash
cast call "$VRF" \
  "getResult(uint256)(bytes32,bytes32,bytes)" \
  0 \
  --rpc-url "$L2_RPC_URL"
```

Call synchronous randomness:

```bash
cast send "$VRF" \
  "getRandomness()(uint256)" \
  --rpc-url "$L2_RPC_URL" \
  --private-key <TEST_PRIVATE_KEY>
```

Verify a tuple manually with the precompile by concatenating:

```text
[33-byte pk][32-byte seed][32-byte beta][81-byte pi]
```

Then call:

```bash
cast call 0x0000000000000000000000000000000000000101 \
  <178_bytes_hex> \
  --rpc-url "$L2_RPC_URL"
```

Expected output is `0x01` for a valid tuple.

## 7. Troubleshooting

### `NoRandomnessAvailable`

The current block has no committed randomness. Check:

```bash
cast call "$VRF" "commitNonce()(uint256)" --rpc-url "$L2_RPC_URL"
tail -n 100 .devnet/sepolia/logs/op-node.log
tail -n 100 .devnet/sepolia/logs/geth.log
```

Common causes:

- op-node was started without a VRF prover while `EnshrainedVRFTime` is scheduled
- TEE endpoint is unavailable or returning proof errors
- op-geth was not rebuilt after VRF payload attribute changes

### Empty `sequencerPublicKey()`

The public key was not synced from Sepolia `SystemConfig` into the L2 predeploy. Check:

```bash
cast call "$VRF" "sequencerPublicKey()(bytes)" --rpc-url "$L2_RPC_URL"
```

Then inspect `.devnet/sepolia/devnet.json` for the SystemConfig address and verify `SystemConfig.vrfPublicKey()` on Sepolia. The prepare script should derive the key from `VRF_SK` and submit `setVRFPublicKey(bytes)` before the local L2 starts.

### Verify Precompile Returns `0x00`

The tuple does not verify under the supplied public key. Re-check byte concatenation order:

```text
pk || seed || beta || pi
```

Also confirm the seed was computed as:

```text
SHA256(uint256(blockNumber) || uint256(nonce))
```

### Predeploy Code Is Missing

Re-run the prepare step to regenerate genesis and initialize the local datadir:

```bash
./scripts/devnet-sepolia-stop.sh
rm -rf .devnet/sepolia
./scripts/devnet-sepolia-prepare.sh
```

## 8. Coverage Checklist

| Layer | Command | Expected |
|-------|---------|----------|
| Crypto | `go test ./crypto/ecvrf/ -v` | pass |
| L2 predeploy | `forge test --match-contract EnshrainedVRFTest -v` | pass |
| L1 verifier helper | `forge test --match-contract VRFVerifierTest -v` | pass |
| op-geth precompile | `go test ./core/vm/ -run ECVRF -v` | pass |
| Engine API JSON | `go test ./beacon/engine/ -run VRF -v` | pass |
| Payload building | `go test ./miner/ -run 'VRF|PayloadIdIncludesVRFAttributes' -v` | pass |
| op-service JSON | `go test ./op-service/eth -run VRF -v` | pass |
| op-node derivation | `go test ./op-node/rollup/derive -run 'VRF|SystemConfig|PreparePayloadAttributes' -v` | pass |
| Sepolia local L2 | `./scripts/devnet-sepolia-verify-random.sh` | pass |
