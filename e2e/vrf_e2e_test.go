// Package e2e provides end-to-end test scenarios for the Enshrined VRF system.
//
// These tests are designed to run against a local devnet with the EnshrainedVRF
// fork activated. They verify the full flow:
//
//	L1 SystemConfig → op-node derivation → op-geth block building → user contract
//
// Prerequisites:
//   - devnet running with EnshrainedVRFTime activated
//   - L2 RPC at http://localhost:8545
//
// Run with: go test -tags e2e ./e2e/ -v
package e2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"testing"
)

const l2RPC = "http://localhost:8545"

// ethCall performs an eth_call RPC against the L2 node.
func ethCall(to string, data string) (string, error) {
	body := fmt.Sprintf(`{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"%s","data":"%s"},"latest"],"id":1}`, to, data)
	resp, err := http.Post(l2RPC, "application/json", bytes.NewBufferString(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	var result struct {
		Result string `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return "", fmt.Errorf("json decode: %w, body: %s", err, string(raw))
	}
	if result.Error != nil {
		return "", fmt.Errorf("rpc error: %s", result.Error.Message)
	}
	return result.Result, nil
}

// ethGetCode checks if a contract has code at the given address.
func ethGetCode(addr string) (string, error) {
	body := fmt.Sprintf(`{"jsonrpc":"2.0","method":"eth_getCode","params":["%s","latest"],"id":1}`, addr)
	resp, err := http.Post(l2RPC, "application/json", bytes.NewBufferString(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	var result struct {
		Result string `json:"result"`
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return "", err
	}
	return result.Result, nil
}

const vrfAddr = "0x42000000000000000000000000000000000000f0"

func isDevnetAvailable() bool {
	_, err := ethGetCode(vrfAddr)
	return err == nil
}

func TestVRFPredeployExists(t *testing.T) {
	if !isDevnetAvailable() {
		t.Skip("devnet not available at " + l2RPC)
	}

	code, err := ethGetCode(vrfAddr)
	if err != nil {
		t.Fatalf("eth_getCode failed: %v", err)
	}

	if code == "0x" || code == "" {
		t.Fatal("PredeployedVRF has no code at expected address")
	}
	t.Logf("PredeployedVRF code length: %d hex chars", len(code)-2)
}

func TestVRFCommitNonce(t *testing.T) {
	if !isDevnetAvailable() {
		t.Skip("devnet not available")
	}

	// commitNonce() selector = 0xd4a7c980 (keccak256("commitNonce()"))
	result, err := ethCall(vrfAddr, "0xd4a7c980")
	if err != nil {
		t.Fatalf("commitNonce() failed: %v", err)
	}

	nonce := new(big.Int)
	nonce.SetString(result[2:], 16)
	t.Logf("commitNonce = %d", nonce)

	if nonce.Sign() == 0 {
		t.Log("WARNING: commitNonce is 0, sequencer may not be committing VRF results")
	}
}

func TestVRFSequencerPublicKey(t *testing.T) {
	if !isDevnetAvailable() {
		t.Skip("devnet not available")
	}

	// sequencerPublicKey() selector = keccak256("sequencerPublicKey()")[:4]
	result, err := ethCall(vrfAddr, "0x88b1e3c0")
	if err != nil {
		t.Fatalf("sequencerPublicKey() failed: %v", err)
	}

	t.Logf("sequencerPublicKey() result: %s", result)
}
