package enclave

import (
	"context"
	"net"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

func TestServerProveAndVerify(t *testing.T) {
	storage := NewSealedStorage(t.TempDir())
	srv, err := NewServer(storage)
	if err != nil {
		t.Fatalf("NewServer: %v", err)
	}

	seed := make([]byte, 32)
	seed[0] = 0x42

	resp, err := srv.Prove(context.Background(), &pb.ProveRequest{Seed: seed})
	if err != nil {
		t.Fatalf("Prove: %v", err)
	}

	if len(resp.Beta) != 32 {
		t.Fatalf("beta length = %d, want 32", len(resp.Beta))
	}
	if len(resp.Pi) != 81 {
		t.Fatalf("pi length = %d, want 81", len(resp.Pi))
	}

	// Verify the proof using the public key
	pkResp, err := srv.GetPublicKey(context.Background(), &pb.GetPublicKeyRequest{})
	if err != nil {
		t.Fatalf("GetPublicKey: %v", err)
	}

	pk, err := secp256k1.ParsePubKey(pkResp.PublicKey)
	if err != nil {
		t.Fatalf("ParsePublicKey: %v", err)
	}

	var pi [81]byte
	copy(pi[:], resp.Pi)
	valid, beta, err := ecvrf.Verify(pk, seed, pi)
	if err != nil {
		t.Fatalf("Verify error: %v", err)
	}
	if !valid {
		t.Fatal("proof should be valid")
	}
	if string(beta[:]) != string(resp.Beta) {
		t.Fatal("beta mismatch between Prove and Verify")
	}
}

func TestServerSealUnsealRoundtrip(t *testing.T) {
	dir := t.TempDir()

	// First run: generate and seal
	storage1 := NewSealedStorage(dir)
	srv1, err := NewServer(storage1)
	if err != nil {
		t.Fatalf("NewServer (first): %v", err)
	}
	pk1, _ := srv1.GetPublicKey(context.Background(), &pb.GetPublicKeyRequest{})

	// Second run: unseal existing
	storage2 := NewSealedStorage(dir)
	srv2, err := NewServer(storage2)
	if err != nil {
		t.Fatalf("NewServer (second): %v", err)
	}
	pk2, _ := srv2.GetPublicKey(context.Background(), &pb.GetPublicKeyRequest{})

	if string(pk1.PublicKey) != string(pk2.PublicKey) {
		t.Fatal("public key should be identical after unseal")
	}

	// Prove with both and verify determinism
	seed := make([]byte, 32)
	seed[0] = 0xff
	r1, _ := srv1.Prove(context.Background(), &pb.ProveRequest{Seed: seed})
	r2, _ := srv2.Prove(context.Background(), &pb.ProveRequest{Seed: seed})

	if string(r1.Beta) != string(r2.Beta) {
		t.Fatal("same key + same seed should produce same beta")
	}
}

func TestServerOverGRPC(t *testing.T) {
	storage := NewSealedStorage(t.TempDir())
	srv, err := NewServer(storage)
	if err != nil {
		t.Fatalf("NewServer: %v", err)
	}

	// Start gRPC server on random port
	lis, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)
	go grpcServer.Serve(lis)
	defer grpcServer.Stop()

	// Connect as client
	conn, err := grpc.NewClient(lis.Addr().String(),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	client := pb.NewVRFEnclaveClient(conn)

	// GetPublicKey
	pkResp, err := client.GetPublicKey(context.Background(), &pb.GetPublicKeyRequest{})
	if err != nil {
		t.Fatalf("GetPublicKey: %v", err)
	}
	if len(pkResp.PublicKey) != 33 {
		t.Fatalf("pk length = %d, want 33", len(pkResp.PublicKey))
	}

	// Prove
	seed := make([]byte, 32)
	for i := range seed {
		seed[i] = byte(i)
	}
	proveResp, err := client.Prove(context.Background(), &pb.ProveRequest{Seed: seed})
	if err != nil {
		t.Fatalf("Prove: %v", err)
	}

	// Verify
	pk, _ := secp256k1.ParsePubKey(pkResp.PublicKey)
	var pi [81]byte
	copy(pi[:], proveResp.Pi)
	valid, _, err := ecvrf.Verify(pk, seed, pi)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if !valid {
		t.Fatal("proof from gRPC should be valid")
	}
}

func TestProveInvalidSeed(t *testing.T) {
	storage := NewSealedStorage(t.TempDir())
	srv, err := NewServer(storage)
	if err != nil {
		t.Fatalf("NewServer: %v", err)
	}

	// Too short
	_, err = srv.Prove(context.Background(), &pb.ProveRequest{Seed: []byte{0x01}})
	if err == nil {
		t.Fatal("expected error for short seed")
	}
}
