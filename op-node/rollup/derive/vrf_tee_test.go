package derive

import (
	"net"
	"testing"

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

	beta, pi, err := ComputeVRFProof(prover, blockNumber)
	if err != nil {
		t.Fatalf("ComputeVRFProof: %v", err)
	}

	// Verify: any node can do this with the public key (no TEE needed)
	seed := ComputeVRFSeed(blockNumber)
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
		beta, pi, err := ComputeVRFProof(prover, blockNum)
		if err != nil {
			t.Fatalf("block %d: ComputeVRFProof: %v", blockNum, err)
		}

		seed := ComputeVRFSeed(blockNum)
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

	teeBeta, teePi, err := ComputeVRFProof(teeProver, blockNumber)
	if err != nil {
		t.Fatalf("TEE ComputeVRFProof: %v", err)
	}

	localBeta, localPi, err := ComputeVRFProof(localProver, blockNumber)
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
