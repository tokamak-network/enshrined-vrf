package vrf

import (
	"context"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/url"
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
	cfg.DisableBatcher = true // Prevent reorg from L1 derivation for stable demo
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

	// Start a TCP proxy on fixed port 9545 → sequencer's random port
	fixedPort := os.Getenv("VRF_PORT")
	if fixedPort == "" {
		fixedPort = "9545"
	}
	proxyAddr := "127.0.0.1:" + fixedPort
	parsed, err := url.Parse(rpcURL)
	require.NoError(t, err)
	stopProxy := startTCPProxy(t, proxyAddr, parsed.Host)
	defer stopProxy()
	fixedRPC := "http://" + proxyAddr

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
	fmt.Printf("  L2 RPC (fixed): %s\n", fixedRPC)
	fmt.Printf("  L2 RPC (actual): %s\n", rpcURL)
	fmt.Printf("  commitNonce: %d (blocks with VRF so far)\n", commitNonce)
	fmt.Printf("  VRF[0] seed: %s\n", seed.Hex())
	fmt.Printf("  VRF[0] beta: %s\n", beta.Hex())
	fmt.Println()
	fmt.Println("  ── Try these commands ──")
	fmt.Println()
	fmt.Printf("  RPC=%s\n", fixedRPC)
	fmt.Printf("  KEY=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6\n")
	fmt.Printf("  VRF=0x42000000000000000000000000000000000000f0\n")
	fmt.Println()
	fmt.Printf("  # 1. Check VRF contract exists\n")
	fmt.Printf("  cast code $VRF --rpc-url $RPC | head -c 40\n")
	fmt.Println()
	fmt.Printf("  # 2. Query commitNonce (increases every block)\n")
	fmt.Printf("  cast call $VRF \"commitNonce()(uint256)\" --rpc-url $RPC\n")
	fmt.Println()
	fmt.Printf("  # 3. Get VRF proof for nonce 0\n")
	fmt.Printf("  cast call $VRF \"getResult(uint256)(bytes32,bytes32,bytes)\" 0 --rpc-url $RPC\n")
	fmt.Println()
	fmt.Printf("  # 4. Send getRandomness() tx\n")
	fmt.Printf("  cast send $VRF \"getRandomness()\" --private-key $KEY --rpc-url $RPC\n")
	fmt.Println()
	fmt.Printf("  # 5. Deploy & test CoinFlip\n")
	fmt.Printf("  forge create contracts/src/examples/CoinFlip.sol:CoinFlip \\\n")
	fmt.Printf("    --private-key $KEY --rpc-url $RPC --root contracts --broadcast\n")
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

// startTCPProxy creates a TCP proxy from listenAddr to targetAddr.
// Returns a stop function.
func startTCPProxy(t *testing.T, listenAddr, targetAddr string) func() {
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		t.Logf("Warning: could not bind fixed port %s: %v (using random port URL instead)", listenAddr, err)
		return func() {}
	}

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return // listener closed
			}
			go func(c net.Conn) {
				defer c.Close()
				upstream, err := net.Dial("tcp", targetAddr)
				if err != nil {
					return
				}
				defer upstream.Close()
				go io.Copy(upstream, c)
				io.Copy(c, upstream)
			}(conn)
		}
	}()

	return func() { ln.Close() }
}
