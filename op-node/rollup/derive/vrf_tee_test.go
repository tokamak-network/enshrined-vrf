package derive

import (
	"fmt"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/common"
	"google.golang.org/grpc"

	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
	"github.com/tokamak-network/enshrined-vrf/vrf-enclave/enclave"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

// startTestEnclave starts a gRPC enclave server on a random port and
// returns the address and a cleanup function.
func startTestEnclave(t *testing.T) (addr string, pk *secp256k1.PublicKey) {
	t.Helper()

	storage := enclave.NewSealedStorage(t.TempDir())
	srv, err := enclave.NewServer(storage)
	if err != nil {
		t.Fatalf("NewServer: %v", err)
	}

	lis, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}

	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)
	go grpcServer.Serve(lis)
	t.Cleanup(grpcServer.Stop)

	// Parse the public key for verification
	pkResp, _ := srv.GetPublicKey(nil, &pb.GetPublicKeyRequest{})
	pubKey, err := secp256k1.ParsePubKey(pkResp.PublicKey)
	if err != nil {
		t.Fatalf("ParsePubKey: %v", err)
	}

	return lis.Addr().String(), pubKey
}

// TestTEEVRFProverEndToEnd tests the full op-node → TEE enclave path:
// TEEVRFProver connects to enclave, ComputeVRFProof generates block-level
// proof, and ecvrf.Verify confirms correctness.
func TestTEEVRFProverEndToEnd(t *testing.T) {
	addr, pk := startTestEnclave(t)

	// Create TEEVRFProver (this is what op-node uses)
	prover, err := NewTEEVRFProver(addr)
	if err != nil {
		t.Fatalf("NewTEEVRFProver: %v", err)
	}
	defer prover.Close()

	// Verify public key is 33 bytes compressed
	if len(prover.PublicKey()) != 33 {
		t.Fatalf("pk length = %d, want 33", len(prover.PublicKey()))
	}

	// Simulate block building: use ComputeVRFProof exactly as attributes.go does
	blockNumber := uint64(42)
	nonce := uint64(41) // nonce = blockNumber - 1

	beta, pi, err := ComputeVRFProof(prover, blockNumber, nonce)
	if err != nil {
		t.Fatalf("ComputeVRFProof: %v", err)
	}

	// Verify: any node can do this with the public key (no TEE needed)
	seed := ComputeVRFSeed(blockNumber, nonce)
	valid, verifiedBeta, err := ecvrf.Verify(pk, seed[:], pi)
	if err != nil {
		t.Fatalf("Verify error: %v", err)
	}
	if !valid {
		t.Fatal("proof should be valid")
	}
	if beta != verifiedBeta {
		t.Fatal("beta mismatch between prover and verifier")
	}
}

// TestTEEVRFProverMultipleBlocks simulates sequential block production
// to ensure each block gets a unique, valid proof.
func TestTEEVRFProverMultipleBlocks(t *testing.T) {
	addr, pk := startTestEnclave(t)

	prover, err := NewTEEVRFProver(addr)
	if err != nil {
		t.Fatalf("NewTEEVRFProver: %v", err)
	}
	defer prover.Close()

	betas := make(map[[32]byte]bool)

	for blockNum := uint64(1); blockNum <= 10; blockNum++ {
		nonce := blockNum - 1
		beta, pi, err := ComputeVRFProof(prover, blockNum, nonce)
		if err != nil {
			t.Fatalf("block %d: ComputeVRFProof: %v", blockNum, err)
		}

		seed := ComputeVRFSeed(blockNum, nonce)
		valid, _, err := ecvrf.Verify(pk, seed[:], pi)
		if err != nil {
			t.Fatalf("block %d: Verify error: %v", blockNum, err)
		}
		if !valid {
			t.Fatalf("block %d: proof invalid", blockNum)
		}

		if betas[beta] {
			t.Fatalf("block %d: duplicate beta — randomness is not unique", blockNum)
		}
		betas[beta] = true
	}
}

// TestTEEVRFProverMatchesLocal verifies that TEE and local provers
// produce identical results for the same key and seed.
func TestTEEVRFProverMatchesLocal(t *testing.T) {
	// Generate a known key
	sk, err := secp256k1.GeneratePrivateKey()
	if err != nil {
		t.Fatalf("GeneratePrivateKey: %v", err)
	}

	// Start enclave with this specific key
	srv := enclave.NewServerFromKey(sk)
	lis, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)
	go grpcServer.Serve(lis)
	defer grpcServer.Stop()

	// TEE prover
	teeProver, err := NewTEEVRFProver(lis.Addr().String())
	if err != nil {
		t.Fatalf("NewTEEVRFProver: %v", err)
	}
	defer teeProver.Close()

	// Local prover with same key
	skBytes := sk.Key.Bytes()
	localProver, err := NewLocalVRFProver(common.Bytes2Hex(skBytes[:]))
	if err != nil {
		t.Fatalf("NewLocalVRFProver: %v", err)
	}

	// Both should produce identical results
	blockNumber := uint64(100)
	nonce := uint64(99)

	teeBeta, teePi, err := ComputeVRFProof(teeProver, blockNumber, nonce)
	if err != nil {
		t.Fatalf("TEE ComputeVRFProof: %v", err)
	}

	localBeta, localPi, err := ComputeVRFProof(localProver, blockNumber, nonce)
	if err != nil {
		t.Fatalf("Local ComputeVRFProof: %v", err)
	}

	if teeBeta != localBeta {
		t.Fatal("beta mismatch: TEE and local provers diverge")
	}
	if teePi != localPi {
		t.Fatal("pi mismatch: TEE and local provers diverge")
	}
}

// failingVRFProver is a mock prover that fails N times then succeeds.
type failingVRFProver struct {
	inner      VRFProver
	failCount  int
	callCount  atomic.Int32
}

func (f *failingVRFProver) Prove(seed []byte) (beta [32]byte, pi [81]byte, err error) {
	n := int(f.callCount.Add(1))
	if n <= f.failCount {
		return beta, pi, fmt.Errorf("simulated TEE failure (attempt %d)", n)
	}
	return f.inner.Prove(seed)
}

func (f *failingVRFProver) PublicKey() []byte {
	return f.inner.PublicKey()
}

// TestComputeVRFProofWithRetry_SuccessAfterRetries verifies that transient
// TEE failures are recovered by retry logic.
func TestComputeVRFProofWithRetry_SuccessAfterRetries(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	skBytes := sk.Key.Bytes()
	localProver, err := NewLocalVRFProver(common.Bytes2Hex(skBytes[:]))
	if err != nil {
		t.Fatalf("NewLocalVRFProver: %v", err)
	}

	// Fail twice, succeed on third attempt
	prover := &failingVRFProver{inner: localProver, failCount: 2}

	ba := &FetchingAttributesBuilder{
		vrfProver: prover,
		vrfRetry: VRFRetryConfig{
			MaxRetries:    2, // 1 initial + 2 retries = 3 attempts
			RetryInterval: 1 * time.Millisecond,
		},
	}

	beta, pi, err := ba.computeVRFProofWithRetry(100, 99)
	if err != nil {
		t.Fatalf("expected success after retries, got: %v", err)
	}

	// Verify the proof is valid
	seed := ComputeVRFSeed(100, 99)
	valid, _, verifyErr := ecvrf.Verify(sk.PubKey(), seed[:], pi)
	if verifyErr != nil {
		t.Fatalf("Verify error: %v", verifyErr)
	}
	if !valid {
		t.Fatal("proof should be valid")
	}
	if beta == [32]byte{} {
		t.Fatal("beta should not be zero")
	}

	// Should have been called 3 times (2 failures + 1 success)
	if prover.callCount.Load() != 3 {
		t.Fatalf("expected 3 calls, got %d", prover.callCount.Load())
	}
}

// TestComputeVRFProofWithRetry_AllFail verifies that block production halts
// when all retry attempts are exhausted.
func TestComputeVRFProofWithRetry_AllFail(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	skBytes := sk.Key.Bytes()
	localProver, err := NewLocalVRFProver(common.Bytes2Hex(skBytes[:]))
	if err != nil {
		t.Fatalf("NewLocalVRFProver: %v", err)
	}

	// Fail more times than retries allow
	prover := &failingVRFProver{inner: localProver, failCount: 10}

	ba := &FetchingAttributesBuilder{
		vrfProver: prover,
		vrfRetry: VRFRetryConfig{
			MaxRetries:    2,
			RetryInterval: 1 * time.Millisecond,
		},
	}

	_, _, err = ba.computeVRFProofWithRetry(100, 99)
	if err == nil {
		t.Fatal("expected error after all retries exhausted")
	}

	// Should have been called 3 times (1 initial + 2 retries)
	if prover.callCount.Load() != 3 {
		t.Fatalf("expected 3 calls, got %d", prover.callCount.Load())
	}
}

// TestComputeVRFProofWithRetry_ImmediateSuccess verifies no unnecessary
// retries when the first attempt succeeds.
func TestComputeVRFProofWithRetry_ImmediateSuccess(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	skBytes := sk.Key.Bytes()
	localProver, err := NewLocalVRFProver(common.Bytes2Hex(skBytes[:]))
	if err != nil {
		t.Fatalf("NewLocalVRFProver: %v", err)
	}

	prover := &failingVRFProver{inner: localProver, failCount: 0}

	ba := &FetchingAttributesBuilder{
		vrfProver: prover,
		vrfRetry:  DefaultVRFRetryConfig(),
	}

	_, _, err = ba.computeVRFProofWithRetry(100, 99)
	if err != nil {
		t.Fatalf("expected immediate success, got: %v", err)
	}

	if prover.callCount.Load() != 1 {
		t.Fatalf("expected 1 call, got %d", prover.callCount.Load())
	}
}
