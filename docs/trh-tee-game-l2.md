# TRH TEE Game L2 Deployment Runbook

This runbook captures the work needed to expose Enshrained VRF as a Tokamak Rollup Hub deployment option for game-focused L2 chains that need protocol randomness.

## Target Outcome

When a game operator deploys a TRH/Thanos L2 and selects TEE-backed randomness:

1. The generated chain activates the `EnshrainedVRF` fork at genesis or at the configured activation time.
2. `SystemConfig.vrfPublicKey()` on L1 is set to the public key reported by the active TEE enclave.
3. `op-node` runs with `--sequencer.vrf-mode=tee` and `--sequencer.vrf-tee-endpoint=<endpoint>`.
4. `op-geth` injects the per-block VRF public-key sync and randomness commitment deposits.
5. Game contracts can call `IEnshrainedVRF(0x42000000000000000000000000000000000000f0).getRandomness()` synchronously.
6. Operators can monitor that commitments advance and that the registered public key matches the enclave.

## Current Repository Support

The protocol changes already exist in this repository:

- L1 `SystemConfig.setVRFPublicKey(bytes)` and `vrfPublicKey()`
- L2 `EnshrainedVRF` predeploy at `0x42000000000000000000000000000000000000f0`
- ECVRF verify precompile at `0x0000000000000000000000000000000000000101`
- `op-node` local and TEE VRF prover modes
- `op-geth` VRF deposit injection
- fault-proof ECVRF precompile routing
- Sepolia-backed local L2 scripts

`scripts/devnet-sepolia-prepare.sh` supports both public-key sources:

- `VRF_MODE=local`: derives the public key from `VRF_SK`; dev only.
- `VRF_MODE=tee`: reads the public key from `VRF_TEE_ENDPOINT`; use this for game L2 deployment rehearsals.
- `VRF_PUBLIC_KEY=0x...`: optional override when the platform has already verified and recorded the enclave key.

TRH integration artifacts live under `deploy/trh/`:

- `enshrined-vrf.manifest.json`: machine-readable stack feature contract for SDK, metadata, and readiness gates.
- `settings.schema.json` and `settings.example.json`: SDK-facing settings contract for TEE-backed game L2 deployments.
- `metadata.example.json`: reference rollup metadata fragment for a game L2 with Enshrained VRF enabled.
- `thanos-stack-vrf-values.example.yaml`: reference sequencer/enclave chart overlay.
- `kubernetes-vrf-sidecar.example.yaml`: concrete Kubernetes example for wiring `op-node` to a `vrf-enclave` sidecar over a private Unix socket.
- `external-integration/`: patch/checker package for applying the feature to the external TRH SDK and Thanos chart repositories.
- `attestation-policy.schema.json` and `attestation-policy.example.json`: reference platform quote policy contract for production TEE rollout.
- `vrf-enclave/Dockerfile`: minimal non-root runtime image for `vrf-enclave` and `vrf-prove`.
- `scripts/trh-build-vrf-enclave-image.sh`: local build/push helper for the enclave image.
- `scripts/trh-attest-vrf-enclave.sh`: fetches enclave attestation, checks public-key binding, and dispatches platform verifier commands for production modes.
- `scripts/trh-validate-attestation-policy.sh`: validates attestation policy shape and production measurement placeholders.
- `scripts/trh-production-vrf-gate.sh`: blocks production rollout when local/dev attestation, unpinned image tags, or missing audit IDs are configured.
- `scripts/trh-render-vrf-metadata.sh`: renders a chain-specific VRF metadata fragment after deployment.
- `scripts/trh-validate-vrf-metadata.sh`: validates the VRF metadata fragment before opening a metadata PR.
- `scripts/trh-render-vrf-settings.sh`: renders a JSON settings fragment for a TEE-backed game L2.
- `scripts/trh-validate-vrf-settings.sh`: validates rendered SDK settings before handing them to a TRH deployer.
- `scripts/trh-validate-k8s-vrf-sidecar.sh`: validates the Kubernetes sidecar example for chart implementation drift.
- `scripts/trh-check-external-integration.sh`: checks whether external TRH repositories have consumed the required VRF integration points.
- `scripts/trh-verify-vrf-chain.sh`: verifies a deployed TRH L2 has active VRF commitments and matching public keys.
- `scripts/trh-verify-vrf-proof.sh`: verifies a committed `(pk, seed, beta, pi)` tuple through the L2 `0x0101` precompile.
- `scripts/trh-export-vrf-metrics.sh`: emits Prometheus text metrics for periodic monitoring.
- `prometheus-rules.example.yaml`: reference alert rules for stalled commitments, missing keys, and randomness failures.

## Local TEE Rehearsal

Start a dev enclave:

```bash
go run ./vrf-enclave/cmd/vrf-enclave \
  --listen localhost:50051 \
  --seal-dir .devnet/vrf-enclave/sealed \
  --dev-seal \
  --attestation dev
```

Configure the Sepolia-backed devnet:

```bash
cp devnet/sepolia/.env.example devnet/sepolia/.env
$EDITOR devnet/sepolia/.env
```

Use these VRF settings:

```bash
VRF_MODE=tee
VRF_TEE_ENDPOINT=localhost:50051
SET_L1_VRF_PUBLIC_KEY=1
```

Then run:

```bash
./scripts/devnet-sepolia-preflight.sh
./scripts/trh-attest-vrf-enclave.sh
./scripts/devnet-sepolia-prepare.sh
./scripts/devnet-sepolia-start.sh
./scripts/devnet-sepolia-verify-random.sh
```

The prepare step registers the TEE enclave public key on Sepolia `SystemConfig`. The verify step checks that the L2 predeploy exists, `commitNonce()` advances, the L2 public key matches the L1 key, `getRandomness()` returns, and a `CoinFlip` consumer can use randomness.

## Game Contract Integration

For new game contracts, use the fixed VRF predeploy on a TRH chain and inject a mock only in tests. `contracts/src/examples/TRHGameRandomness.sol` contains a small adapter and dice example:

```solidity
contract MyGame is TRHGameRandomness {
    constructor() TRHGameRandomness(address(0)) {}

    function draw(uint256 maxExclusive) external returns (uint256) {
        return _randomBelow(maxExclusive);
    }
}
```

Use `new TRHDiceGame(address(mockVrf))` in tests and `new TRHDiceGame(address(0))` for a deployed TRH game L2.

## TRH Integration Checklist

### SDK and Platform

- Add a TRH `thanos` feature flag such as `enableEnshrinedVrf`; a separate `thanos-vrf` stack alias can be added later, but the current SDK already supports the `thanos` stack name.
- Surface required inputs: chain name, L2 chain ID, L1 RPC, beacon URL, AWS credentials, TEE endpoint, and optional verified VRF public key.
- Reject production deployments when `VRF_MODE=local` or when no TEE endpoint/public key is available.
- Persist `vrf_mode`, `vrf_tee_endpoint`, `vrf_public_key`, `enshrined_vrf_time`, and VRF image versions in `settings.json`.
- During contract deployment, set `l2GenesisEnshrainedVRFTimeOffset` and register `SystemConfig.setVRFPublicKey(bytes)`.

### Images and Infrastructure

- Publish patched `op-geth`, `op-node`, `op-deployer`, and contracts-bedrock artifacts under versioned image tags.
- Add a `vrf-enclave` sidecar or service to the sequencer deployment.
- Mount sealed-key storage on durable encrypted storage.
- Wire op-node with `--sequencer.vrf-mode=tee --sequencer.vrf-tee-endpoint=<endpoint>`.
- Expose enclave health only inside the cluster; do not expose the proving endpoint publicly.

Validate the reference Kubernetes sidecar wiring:

```bash
./scripts/trh-validate-k8s-vrf-sidecar.sh deploy/trh/kubernetes-vrf-sidecar.example.yaml
```

Build the enclave image locally:

```bash
IMAGE_REPOSITORY=tokamaknetwork/vrf-enclave \
IMAGE_TAG=dev \
./scripts/trh-build-vrf-enclave-image.sh
```

Push a release tag only after tests and readiness gates pass:

```bash
IMAGE_REPOSITORY=registry.example/vrf-enclave \
IMAGE_TAG=v0.1.0 \
PUSH=1 \
./scripts/trh-build-vrf-enclave-image.sh
```

### Metadata and Tooling

- Extend the rollup metadata schema with `features.enshrinedVrf`, `vrfPredeploy`, `vrfVerifyPrecompile`, and `vrfPublicKey`.
- Extend metadata checker validation to confirm:
  - `SystemConfig.vrfPublicKey()` is 33 bytes.
  - L2 `sequencerPublicKey()` matches L1.
  - `commitNonce()` advances.
  - `0x0101` verifies a committed `(pk, seed, beta, pi)` tuple.
- Register the chain metadata PR after deployment and checker success.

Validate the metadata fragment before submission:

```bash
./scripts/trh-validate-vrf-metadata.sh deploy/trh/metadata.example.json
```

Render metadata for a deployed game L2:

```bash
CHAIN_NAME=game-l2 \
CHAIN_ID=901005 \
VRF_PUBLIC_KEY=0x02... \
./scripts/trh-render-vrf-metadata.sh > .devnet/game-l2-vrf-metadata.json
./scripts/trh-validate-vrf-metadata.sh .devnet/game-l2-vrf-metadata.json
```

### Monitoring

Track these signals at minimum:

- TEE enclave process health and restart count
- TEE proof latency and proof error count
- L2 `commitNonce()` monotonic increase
- L1 `SystemConfig.vrfPublicKey()` vs TEE `GetPublicKey`
- L2 `EnshrainedVRF.sequencerPublicKey()` vs L1 public key
- latest committed tuple verification through the L2 `0x0101` precompile
- missing commitment alerts per block window

For a simple Prometheus textfile collector flow:

```bash
L1_RPC_URL=https://sepolia.example \
L2_RPC_URL=https://game-l2.example \
SYSTEM_CONFIG_PROXY=0x... \
./scripts/trh-export-vrf-metrics.sh > /var/lib/node_exporter/textfile_collector/enshrined_vrf.prom
```

Use `deploy/trh/prometheus-rules.example.yaml` as the starting alert group.

## Production Gaps Before Mainnet

The current enclave supports dev attestation only. Before public production, add and audit a real platform attestation mode, such as SGX, TDX, or SEV-SNP. The production release gate should require:

- platform quote verification
- key sealing tied to platform identity
- key backup or rotation runbook
- external cryptography and protocol audit
- recovery drills for enclave restart, key mismatch, and proof failures

Before registering the public key on L1, fetch an attestation report and verify that the report key matches the enclave public key:

```bash
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_ATTESTATION_MODE=dev \
./scripts/trh-attest-vrf-enclave.sh
```

For production platform modes, provide a verifier command. The script passes `VRF_ATTESTATION_MODE`, `VRF_ATTESTATION_PUBLIC_KEY`, `VRF_ATTESTATION_CHALLENGE`, and `VRF_ATTESTATION_REPORT` as environment variables to the verifier:

```bash
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_ATTESTATION_MODE=tdx \
PLATFORM_ATTESTATION_VERIFIER=./scripts/verify-tdx-quote.sh \
./scripts/trh-attest-vrf-enclave.sh
```

Validate the attestation policy before wiring it into production gates:

```bash
./scripts/trh-validate-attestation-policy.sh deploy/trh/attestation-policy.example.json
PRODUCTION=1 ./scripts/trh-validate-attestation-policy.sh deploy/trh/attestation-policy.production.json
```

Run the production gate before publishing a public deployment:

```bash
VRF_MODE=tee \
VRF_ATTESTATION_MODE=tdx \
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_PUBLIC_KEY=0x02... \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
VRF_ATTESTATION_POLICY_ID=tdx-game-l2-vrf-policy-v1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-... \
./scripts/trh-production-vrf-gate.sh
```

The current development enclave does not implement SGX/TDX/SEV-SNP quote verification. Leave `VRF_PLATFORM_ATTESTATION_IMPLEMENTED` unset until a real platform verifier and policy have been implemented and audited.

## Readiness Command

Use this before handing a build to TRH integration:

```bash
VRF_MODE=tee \
VRF_TEE_ENDPOINT=localhost:50051 \
./scripts/trh-tee-readiness.sh
```

For static checks only, without requiring a running enclave:

```bash
REQUIRE_TEE=0 ./scripts/trh-tee-readiness.sh
```

To run the full local readiness bundle without live TEE or Docker image build:

```bash
./scripts/trh-local-readiness.sh
```

Set `RUN_EXTERNAL_PATCH_COMPILE=0` to skip temporary compile checks against
local `../trh-sdk`, `../trh-backend`, and `../trh-platform-ui` checkouts. Set
`RUN_DOCKER_BUILD=1` when Docker is available and the enclave image build
should be included.

Render a TRH settings fragment after attesting or otherwise confirming the enclave public key:

```bash
VRF_MODE=tee \
VRF_TEE_ENDPOINT=localhost:50051 \
./scripts/trh-render-vrf-settings.sh > .devnet/trh-vrf-settings.json
./scripts/trh-validate-vrf-settings.sh .devnet/trh-vrf-settings.json
```

If the platform already has the verified key:

```bash
VRF_MODE=tee \
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_PUBLIC_KEY=0x02... \
./scripts/trh-render-vrf-settings.sh | ./scripts/trh-validate-vrf-settings.sh -
```

Verify a deployed TRH game L2 after the sequencer is running:

```bash
L1_RPC_URL=https://sepolia.example \
L2_RPC_URL=https://game-l2.example \
SYSTEM_CONFIG_PROXY=0x... \
./scripts/trh-verify-vrf-chain.sh
```

For an L2-only check with a pre-verified key:

```bash
L2_RPC_URL=https://game-l2.example \
EXPECTED_VRF_PUBLIC_KEY=0x02... \
./scripts/trh-verify-vrf-chain.sh
```

Verify that the latest committed tuple passes the ECVRF precompile:

```bash
L2_RPC_URL=https://game-l2.example \
./scripts/trh-verify-vrf-proof.sh
```

Export one-shot monitoring metrics for a deployed TRH game L2:

```bash
L1_RPC_URL=https://sepolia.example \
L2_RPC_URL=https://game-l2.example \
SYSTEM_CONFIG_PROXY=0x... \
./scripts/trh-export-vrf-metrics.sh
```
