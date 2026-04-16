package proofs_test

import (
	"testing"

	"github.com/ethereum-optimism/optimism/op-e2e/actions/helpers"
	proofHelpers "github.com/ethereum-optimism/optimism/op-e2e/actions/proofs/helpers"
	"github.com/ethereum-optimism/optimism/op-node/rollup/derive"
	"github.com/ethereum-optimism/optimism/op-service/bigs"
	"github.com/stretchr/testify/require"
)

// runVRFFaultProofTest builds an L2 block with VRF randomness committed via
// a deposit transaction, submits the batch to L1, then runs op-program to
// re-derive the same state. This validates the full fault-proof pipeline:
//
//	TEE → deposit tx → batch → L1 → op-program re-derivation → same state root
func runVRFFaultProofTest(gt *testing.T, testCfg *proofHelpers.TestCfg[any]) {
	t := helpers.NewDefaultTesting(gt)
	bcfg := proofHelpers.NewBatcherCfg()

	env := proofHelpers.NewL2FaultProofEnv(t, testCfg, proofHelpers.NewTestParams(), bcfg)

	// Configure VRF prover on the sequencer (simulates TEE in test mode).
	// Uses the RFC 9381 test vector key — same as the system E2E tests.
	testVRFKey := "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721"
	prover, err := derive.NewLocalVRFProver(testVRFKey)
	require.NoError(t, err)
	env.Sequencer.SetVRFProver(prover)

	// Build an L2 block. With EnshrainedVRF active, the sequencer will:
	// 1. Compute VRF proof via the local prover
	// 2. Include a VRF deposit tx (commitRandomness) in the block
	env.Sequencer.ActL2StartBlock(t)
	env.Sequencer.ActL2EndBlock(t)

	// Submit the batch to L1 and include it in an L1 block.
	env.Batcher.ActSubmitAll(t)
	env.Miner.ActL1StartBlock(12)(t)
	env.Miner.ActL1IncludeTxByHash(env.Batcher.LastSubmitted.Hash())(t)
	env.Miner.ActL1EndBlock(t)

	// Finalize the L1 block containing the batch.
	env.Miner.ActL1SafeNext(t)
	env.Miner.ActL1FinalizeNext(t)

	// Derive the L2 chain from L1 data.
	env.Sequencer.ActL1HeadSignal(t)
	env.Sequencer.ActL2PipelineFull(t)

	l2SafeHead := env.Engine.L2Chain().CurrentSafeBlock()
	require.Equal(t, uint64(1), bigs.Uint64Strict(l2SafeHead.Number),
		"L2 block 1 should be safe after batch submission")

	// Run the fault proof program. This re-derives L2 block 1 from L1 data
	// without a VRF prover — instead relying on VRF data embedded in the batch.
	// If fault proof compatibility is correct, the derived state root matches.
	env.RunFaultProofProgramFromGenesis(t, bigs.Uint64Strict(l2SafeHead.Number), testCfg.CheckResult, testCfg.InputParams...)
}

func Test_ProgramAction_VRFBlock(gt *testing.T) {
	matrix := proofHelpers.NewMatrix[any]()
	defer matrix.Run(gt)

	matrix.AddTestCase(
		"VRF-FaultProof",
		nil,
		proofHelpers.NewForkMatrix(proofHelpers.EnshrainedVRF),
		runVRFFaultProofTest,
		proofHelpers.ExpectNoError(),
	)
}
