# OP Stack Customizations for Enshrined VRF

This document describes the OP Stack changes that make Enshrained VRF a protocol feature instead of an external oracle integration. It is the source of truth for the modified consensus, derivation, execution, and deployment surfaces.

## Design Summary

Enshrained VRF adds a post-Interop fork named `EnshrainedVRF`. After activation, the sequencer produces one VRF commitment for each L2 block and exposes it through the L2 predeploy at `0x42000000000000000000000000000000000000f0`.

The secret key is not part of the EVM state. In production, op-node delegates `ECVRF.Prove(sk, seed)` to a TEE enclave. In local development, op-node can use an in-memory key with `--sequencer.vrf-mode=local`, but that mode does not provide operator-hidden unpredictability.

The execution client does not hold the VRF secret key. op-node computes the proof, passes the proof material through Engine API payload attributes, and op-geth turns those attributes into deterministic deposit transactions.

## Consensus-Critical Flow

1. The L1 `SystemConfig` owner registers the sequencer VRF public key with `setVRFPublicKey(bytes)`.
2. op-node parses `ConfigUpdate(UpdateType.VRF_PUBLIC_KEY, data)` logs and stores the 33-byte compressed SEC1 key in `eth.SystemConfig.VRFPublicKey`.
3. For each EnshrainedVRF block, op-node computes:

```text
seed = SHA256(uint256(blockNumber) || uint256(nonce))
(beta, pi) = ECVRF.Prove(sk, seed)
```

4. op-node sends the following Engine API payload attributes to op-geth:

| Field | Size | Description |
|-------|------|-------------|
| `vrfPublicKey` | 33 bytes | Compressed SEC1 public key from L1 `SystemConfig` |
| `vrfSeed` | 32 bytes | Seed computed from L2 block number and VRF nonce |
| `vrfProofBeta` | 32 bytes | VRF output hash |
| `vrfProofPi` | 81 bytes | ECVRF proof |
| `vrfNonce` | uint64 | Monotonic commitment nonce |

These byte fields are JSON hex strings, not base64.

5. op-geth injects EnshrainedVRF deposits during block building:

| Deposit | Calldata | Source-hash domain | Purpose |
|---------|----------|--------------------|---------|
| Public key sync | `setSequencerPublicKey(bytes pk)` | `0x03` | Copies the L1-configured key into the L2 predeploy |
| Randomness commit | `commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes pi)` | `0x02` | Stores the block VRF result in the L2 predeploy |

The deposits are inserted after forced payload transactions such as L1 info deposits and before txpool transactions.

6. User contracts call `EnshrainedVRF.getRandomness()` in the same L2 block. The predeploy returns:

```text
uint256(keccak256(beta || callCounter))
```

`callCounter` resets whenever a new commitment is stored, so multiple calls in the same block receive distinct values derived from the same committed beta.

## Modified OP Stack Surfaces

| Surface | Files | Change |
|---------|-------|--------|
| Fork config | `op-geth/params/config.go`, `optimism/op-node/rollup/types.go`, `optimism/op-chain-ops/genesis/config.go` | Adds `EnshrainedVRFTime` / `enshrined_vrf_time` activation |
| L1 config | `optimism/packages/contracts-bedrock/src/L1/SystemConfig.sol` | Adds `VRF_PUBLIC_KEY`, `setVRFPublicKey(bytes)`, and `vrfPublicKey()` |
| L2 predeploy | `optimism/packages/contracts-bedrock/src/L2/EnshrainedVRF.sol`, `interfaces/L2/IEnshrainedVRF.sol`, `Predeploys.sol`, `L2Genesis.s.sol` | Adds the `EnshrainedVRF` predeploy at `0x42...f0` |
| Engine API | `optimism/op-service/eth/types.go`, `op-geth/beacon/engine/types.go`, `op-geth/eth/catalyst/api.go` | Adds VRF payload attributes and hex JSON encoding |
| Derivation and batching | `optimism/op-node/rollup/derive/attributes.go`, `singular_batch.go`, `span_batch.go`, `channel_out.go`, `attributes_queue.go` | Computes and carries VRF commitment material through batches |
| Proving mode | `optimism/op-node/vrf_prover.go`, `optimism/op-node/flags/flags.go`, `optimism/op-node/rollup/derive/vrf_tee.go` | Adds local and TEE VRF provers |
| Block building | `op-geth/miner/vrf_builder.go`, `op-geth/miner/worker.go`, `op-geth/miner/payload_building.go` | Converts VRF payload attributes into deterministic deposit transactions |
| Verify precompile | `op-geth/core/vm/contracts_ecvrf.go`, `op-geth/core/vm/contracts.go`, `op-geth/params/protocol_params.go` | Adds ECVRF verify precompile at `0x0101` with 3,000 gas |
| Fault proof support | `optimism/op-program/client/l2/engineapi/precompiles.go`, `optimism/op-program/host/prefetcher/prefetcher.go` | Routes the ECVRF precompile through the preimage-oracle path during op-program execution |

## L2 Predeploy Interface

```solidity
interface IEnshrainedVRF {
    event RandomnessCommitted(uint256 indexed nonce, bytes32 beta, address indexed caller);
    event SequencerPublicKeyUpdated(bytes pk);

    function getRandomness() external returns (uint256 randomness);
    function getResult(uint256 nonce) external view returns (bytes32 seed, bytes32 beta, bytes memory pi);
    function sequencerPublicKey() external view returns (bytes memory pk);
    function commitNonce() external view returns (uint256);
    function callCounter() external view returns (uint256);

    function commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes calldata pi) external;
    function setSequencerPublicKey(bytes calldata pk) external;
}
```

`commitRandomness` and `setSequencerPublicKey` are system-only entry points. They must be called by `DEPOSITOR_ACCOUNT` (`0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001`) through deposit transactions.

The `nonce` argument to `commitRandomness` is committed for seed reconstruction and auditability. The contract stores results under its own `_commitNonce`, which increments monotonically after each accepted commitment.

## Verification Boundaries

The predeploy validates access control, public-key length, and proof length. It does not run the ECVRF verify precompile during `commitRandomness`; normal block execution stays deterministic and cheap.

VRF correctness is externally verifiable from the committed tuple `(pk, seed, beta, pi)`:

- L2 contracts or off-chain monitors can call the `0x0101` verify precompile.
- L1 dispute tooling can use `contracts/src/L1/VRFVerifier.sol` for seed and proof-structure checks.
- op-program includes an ECVRF precompile oracle path so fault-proof re-execution can execute contracts that call the verify precompile.

This means operators must register the L1 `SystemConfig` VRF public key before relying on production randomness. The Sepolia devnet prepare script derives the public key from `VRF_SK` and submits `SystemConfig.setVRFPublicKey(bytes)` before the local L2 is started.

## Operational Invariants

- `EnshrainedVRFTime` must be set consistently in rollup config and op-geth chain config.
- A sequencer with the EnshrainedVRF fork scheduled must start op-node with a VRF prover:
  - local dev: `--sequencer.vrf-mode=local --sequencer.vrf-key=<hex-sk>`
  - production: `--sequencer.vrf-mode=tee --sequencer.vrf-tee-endpoint=<endpoint>`
- The public key registered on L1 must match the active prover key.
- Byte payload fields must remain hex encoded in JSON.
- `vrfSeed`, `vrfProofBeta`, `vrfProofPi`, and `vrfNonce` must be included in payload IDs so parallel payload builds cannot collide across different VRF attributes.
- The L2 predeploy address is fixed at `0x42000000000000000000000000000000000000f0`; the ECVRF verify precompile address is fixed at `0x0000000000000000000000000000000000000101`.

## Primary Verification Commands

```bash
go test ./crypto/ecvrf/ -v

cd op-geth
go test ./core/vm/ -run ECVRF -v
go test ./beacon/engine/ -run VRF -v
go test ./miner/ -run VRF -v

cd ../optimism/op-service/eth
go test -run VRF -v

cd ../../op-node/rollup/derive
go test -run 'VRF|SystemConfig|PreparePayloadAttributes' -v
```

For a Sepolia-backed local L2 runbook, see [sepolia-devnet.md](sepolia-devnet.md).
