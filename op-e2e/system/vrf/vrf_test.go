package vrf

import (
	"context"
	"math/big"
	"testing"
	"time"

	op_e2e "github.com/ethereum-optimism/optimism/op-e2e"
	"github.com/ethereum-optimism/optimism/op-e2e/config/secrets"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum-optimism/optimism/op-e2e/system/e2esys"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/stretchr/testify/require"
)

var (
	vrfAddr     = common.HexToAddress("0x42000000000000000000000000000000000000f0")
	genesisTime = hexutil.Uint64(0)
)

// waitForVRFCommitment polls until at least one VRF commitment exists.
func waitForVRFCommitment(ctx context.Context, t *testing.T, client interface {
	CallContract(ctx context.Context, msg ethereum.CallMsg, blockNumber *big.Int) ([]byte, error)
}) {
	t.Helper()
	commitNonceSelector := common.FromHex("0x9fc0ef10")
	err := wait.For(ctx, time.Second, func() (bool, error) {
		result, err := client.CallContract(ctx, ethereum.CallMsg{
			To:   &vrfAddr,
			Data: commitNonceSelector,
		}, nil)
		if err != nil {
			return false, nil
		}
		return new(big.Int).SetBytes(result).Sign() > 0, nil
	})
	require.NoError(t, err, "need at least 1 VRF commitment")
}

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

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Poll until commitNonce > 0
	commitNonceSelector := common.FromHex("0x9fc0ef10")
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

// TestEnshrainedVRF_GetRandomness verifies the full flow:
// sequencer commits VRF → user calls getRandomness() → tx succeeds.
func TestEnshrainedVRF_GetRandomness(t *testing.T) {
	op_e2e.InitParallel(t)

	cfg := e2esys.EnshrainedVRFSystemConfig(t, &genesisTime)
	sys, err := cfg.Start(t)
	require.NoError(t, err)

	client := sys.NodeClient("sequencer")

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	waitForVRFCommitment(ctx, t, client)

	aliceKey := secrets.DefaultSecrets.Alice
	aliceAddr := crypto.PubkeyToAddress(aliceKey.PublicKey)

	chainID, err := client.ChainID(ctx)
	require.NoError(t, err)

	// Send 3 getRandomness() transactions
	getRandomnessSelector := common.FromHex("0xaaae7b86")

	for i := 0; i < 3; i++ {
		nonce, err := client.PendingNonceAt(ctx, aliceAddr)
		require.NoError(t, err)

		gasPrice, err := client.SuggestGasPrice(ctx)
		require.NoError(t, err)

		tx := types.NewTx(&types.LegacyTx{
			Nonce:    nonce,
			GasPrice: gasPrice,
			Gas:      100_000,
			To:       &vrfAddr,
			Data:     getRandomnessSelector,
		})

		signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), aliceKey)
		require.NoError(t, err)

		err = client.SendTransaction(ctx, signedTx)
		require.NoError(t, err)

		receipt, err := wait.ForReceiptOK(ctx, client, signedTx.Hash())
		require.NoError(t, err)
		require.Equal(t, types.ReceiptStatusSuccessful, receipt.Status,
			"getRandomness() tx should succeed")

		t.Logf("getRandomness() call #%d: tx=%s block=%d gasUsed=%d",
			i+1, signedTx.Hash().Hex()[:18], receipt.BlockNumber.Uint64(), receipt.GasUsed)
	}
}

// TestEnshrainedVRF_ProofDataStored verifies that VRF proof data (seed, beta)
// is correctly stored and retrievable via getResult().
func TestEnshrainedVRF_ProofDataStored(t *testing.T) {
	op_e2e.InitParallel(t)

	cfg := e2esys.EnshrainedVRFSystemConfig(t, &genesisTime)
	sys, err := cfg.Start(t)
	require.NoError(t, err)

	client := sys.NodeClient("sequencer")

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	waitForVRFCommitment(ctx, t, client)

	// Query getResult(0) to verify proof data is stored
	// getResult(uint256) selector = 0x995e4339
	getResultData := common.FromHex("0x995e4339")
	getResultData = append(getResultData, common.BigToHash(big.NewInt(0)).Bytes()...)

	result, err := client.CallContract(ctx, ethereum.CallMsg{
		To:   &vrfAddr,
		Data: getResultData,
	}, nil)
	require.NoError(t, err)
	require.True(t, len(result) > 64, "getResult(0) should return seed + beta + pi")

	// Parse seed and beta from ABI-encoded response
	seed := common.BytesToHash(result[0:32])
	beta := common.BytesToHash(result[32:64])
	t.Logf("VRF Result nonce=0: seed=%s beta=%s", seed.Hex()[:18], beta.Hex()[:18])

	require.NotEqual(t, common.Hash{}, seed, "seed should not be zero")
	require.NotEqual(t, common.Hash{}, beta, "beta should not be zero")
}
