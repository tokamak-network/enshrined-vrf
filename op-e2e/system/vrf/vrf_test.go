package vrf

import (
	"context"
	"math/big"
	"testing"
	"time"

	op_e2e "github.com/ethereum-optimism/optimism/op-e2e"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum-optimism/optimism/op-e2e/system/e2esys"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/stretchr/testify/require"
)

var (
	vrfAddr     = common.HexToAddress("0x42000000000000000000000000000000000000f0")
	genesisTime = hexutil.Uint64(0)
)

// TestEnshrainedVRF_PredeployExists verifies that the EnshrainedVRF contract
// is deployed at the predeploy address after genesis.
func TestEnshrainedVRF_PredeployExists(t *testing.T) {
	op_e2e.InitParallel(t)

	cfg := e2esys.EnshrainedVRFSystemConfig(t, &genesisTime)
	sys, err := cfg.Start(t)
	require.NoError(t, err)

	client := sys.NodeClient("sequencer")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	code, err := client.CodeAt(ctx, vrfAddr, nil)
	require.NoError(t, err)
	require.True(t, len(code) > 0, "EnshrainedVRF should have code at predeploy address")
	t.Logf("EnshrainedVRF code length: %d bytes", len(code))
}

// TestEnshrainedVRF_CommitNonceIncreases verifies that the sequencer is
// committing VRF randomness to each block (commitNonce increases over time).
func TestEnshrainedVRF_CommitNonceIncreases(t *testing.T) {
	op_e2e.InitParallel(t)

	cfg := e2esys.EnshrainedVRFSystemConfig(t, &genesisTime)
	sys, err := cfg.Start(t)
	require.NoError(t, err)

	client := sys.NodeClient("sequencer")

	// Wait for a few blocks to be produced
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// commitNonce() selector = keccak256("commitNonce()")[:4] = 0x9fc0ef10
	commitNonceSelector := common.FromHex("0x9fc0ef10")

	// Poll until commitNonce > 0
	var nonce *big.Int
	err = wait.For(ctx, time.Second, func() (bool, error) {
		result, err := client.CallContract(ctx, ethereum.CallMsg{
			To:   &vrfAddr,
			Data: commitNonceSelector,
		}, nil)
		if err != nil {
			return false, nil
		}
		nonce = new(big.Int).SetBytes(result)
		return nonce.Sign() > 0, nil
	})
	require.NoError(t, err, "commitNonce should become > 0")
	t.Logf("commitNonce = %d", nonce)
}
