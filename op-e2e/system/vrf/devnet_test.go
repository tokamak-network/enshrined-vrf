package vrf

import (
	"context"
	"fmt"
	"math/big"
	"os"
	"os/signal"
	"syscall"
	"testing"
	"time"

	op_e2e "github.com/ethereum-optimism/optimism/op-e2e"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum-optimism/optimism/op-e2e/system/e2esys"
	"github.com/ethereum-optimism/optimism/op-service/endpoint"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/stretchr/testify/require"
)

// TestEnshrainedVRF_InteractiveDevnet starts a full OP Stack devnet with
// EnshrainedVRF enabled and keeps it running for interactive exploration.
//
// Run with:
//
//	VRF_INTERACTIVE=1 go test -v -count=1 -run TestEnshrainedVRF_InteractiveDevnet -timeout 0 ./op-e2e/system/vrf/
//
// Press Ctrl+C to stop.
func TestEnshrainedVRF_InteractiveDevnet(t *testing.T) {
	if os.Getenv("VRF_INTERACTIVE") == "" {
		t.Skip("Set VRF_INTERACTIVE=1 to run interactive devnet")
	}

	op_e2e.InitParallel(t)

	zero := hexutil.Uint64(0)
	cfg := e2esys.EnshrainedVRFSystemConfig(t, &zero)
	sys, err := cfg.Start(t)
	require.NoError(t, err)

	// List all EthInstances and their HTTP endpoints for debugging
	var rpcURL string
	for name, inst := range sys.EthInstances {
		userEP := inst.UserRPC()
		t.Logf("EthInstance %q: RPC=%s", name, userEP.RPC())
		if httpEP, ok := userEP.(endpoint.HttpRPC); ok {
			t.Logf("  HTTP: %s", httpEP.HttpRPC())
		}
		if name == e2esys.RoleSeq {
			if httpEP, ok := userEP.(endpoint.HttpRPC); ok {
				rpcURL = httpEP.HttpRPC()
			} else {
				rpcURL = userEP.RPC()
			}
		}
	}
	require.NotEmpty(t, rpcURL, "sequencer RPC URL should be available")

	client := sys.NodeClient("sequencer")
	ctx := context.Background()

	// Wait for VRF to start committing
	commitNonceSelector := common.FromHex("0x9fc0ef10")
	waitCtx, waitCancel := context.WithTimeout(ctx, 30*time.Second)
	defer waitCancel()

	var commitNonce *big.Int
	err = wait.For(waitCtx, time.Second, func() (bool, error) {
		result, err := client.CallContract(waitCtx, ethereum.CallMsg{
			To:   &vrfAddr,
			Data: commitNonceSelector,
		}, nil)
		if err != nil {
			return false, nil
		}
		commitNonce = new(big.Int).SetBytes(result)
		return commitNonce.Sign() > 0, nil
	})
	require.NoError(t, err)

	// Query first VRF result
	getResultData := common.FromHex("0x995e4339")
	getResultData = append(getResultData, common.BigToHash(big.NewInt(0)).Bytes()...)
	result, err := client.CallContract(ctx, ethereum.CallMsg{
		To:   &vrfAddr,
		Data: getResultData,
	}, nil)
	require.NoError(t, err)

	seed := common.BytesToHash(result[0:32])
	beta := common.BytesToHash(result[32:64])

	fmt.Println()
	fmt.Println("============================================")
	fmt.Println("  Enshrined VRF — Interactive Devnet")
	fmt.Println("============================================")
	fmt.Println()
	fmt.Printf("  L2 RPC:      %s\n", rpcURL)
	fmt.Printf("  commitNonce: %d (blocks with VRF so far)\n", commitNonce)
	fmt.Printf("  VRF[0] seed: %s\n", seed.Hex())
	fmt.Printf("  VRF[0] beta: %s\n", beta.Hex())
	fmt.Println()
	fmt.Println("  ── Try these commands ──")
	fmt.Println()
	fmt.Printf("  # 1. Check VRF contract exists\n")
	fmt.Printf("  cast code 0x42000000000000000000000000000000000000f0 --rpc-url %s | head -c 40\n", rpcURL)
	fmt.Println()
	fmt.Printf("  # 2. Query commitNonce (increases every block)\n")
	fmt.Printf("  cast call 0x42000000000000000000000000000000000000f0 \"commitNonce()(uint256)\" --rpc-url %s\n", rpcURL)
	fmt.Println()
	fmt.Printf("  # 3. Get VRF proof for nonce 0\n")
	fmt.Printf("  cast call 0x42000000000000000000000000000000000000f0 \"getResult(uint256)(bytes32,bytes32,bytes)\" 0 --rpc-url %s\n", rpcURL)
	fmt.Println()
	fmt.Printf("  # 4. Call getRandomness() — returns unique value each call\n")
	fmt.Printf("  #    (Alice's test key, pre-funded in devnet)\n")
	fmt.Printf("  cast send 0x42000000000000000000000000000000000000f0 \"getRandomness()(uint256)\" \\\n")
	fmt.Printf("    --private-key 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6 \\\n")
	fmt.Printf("    --rpc-url %s\n", rpcURL)
	fmt.Println()
	fmt.Printf("  # 5. Call getRandomness() via eth_call (read-only, no tx)\n")
	fmt.Printf("  cast call 0x42000000000000000000000000000000000000f0 \"getRandomness()(uint256)\" --rpc-url %s\n", rpcURL)
	fmt.Println()
	fmt.Println("  Press Ctrl+C to stop the devnet.")
	fmt.Println("============================================")
	fmt.Println()

	// Wait for Ctrl+C
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	fmt.Println("\nShutting down devnet...")
}
