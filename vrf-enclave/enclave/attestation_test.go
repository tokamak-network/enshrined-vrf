package enclave

import (
	"context"
	"crypto/rand"
	"net"
	"testing"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"

	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

func TestDevAttestationRoundtrip(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()

	challenge := make([]byte, 32)
	rand.Read(challenge)

	report := CreateDevAttestation(skBytes[:], pk, challenge)

	if len(report) != devReportLen {
		t.Fatalf("report length = %d, want %d", len(report), devReportLen)
	}

	// Verify with key (full check)
	if err := VerifyDevAttestationWithKey(report, challenge, skBytes[:]); err != nil {
		t.Fatalf("VerifyDevAttestationWithKey: %v", err)
	}

	// Verify without key (structural check)
	if err := VerifyDevAttestation(report, challenge, pk); err != nil {
		t.Fatalf("VerifyDevAttestation: %v", err)
	}
}

func TestDevAttestationWrongChallenge(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()

	challenge := make([]byte, 32)
	rand.Read(challenge)
	report := CreateDevAttestation(skBytes[:], pk, challenge)

	// Different challenge should fail HMAC verification
	wrongChallenge := make([]byte, 32)
	rand.Read(wrongChallenge)
	if err := VerifyDevAttestationWithKey(report, wrongChallenge, skBytes[:]); err == nil {
		t.Fatal("expected HMAC failure with wrong challenge")
	}
}

func TestDevAttestationWrongKey(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()

	challenge := make([]byte, 32)
	rand.Read(challenge)
	report := CreateDevAttestation(skBytes[:], pk, challenge)

	// Different secret key should fail
	otherSK, _ := secp256k1.GeneratePrivateKey()
	otherSKBytes := otherSK.Key.Bytes()
	if err := VerifyDevAttestationWithKey(report, challenge, otherSKBytes[:]); err == nil {
		t.Fatal("expected HMAC failure with wrong key")
	}

	// Wrong public key expectation should fail structural check
	otherPK := otherSK.PubKey().SerializeCompressed()
	if err := VerifyDevAttestation(report, challenge, otherPK); err == nil {
		t.Fatal("expected PK mismatch")
	}
}

func TestDevAttestationOverGRPC(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	srv := NewServerFromKey(sk, AttestDev)

	lis, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)
	go grpcServer.Serve(lis)
	defer grpcServer.Stop()

	conn, err := grpc.NewClient(lis.Addr().String(),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	client := pb.NewVRFEnclaveClient(conn)

	// Send challenge and get attestation
	challenge := make([]byte, 32)
	rand.Read(challenge)

	resp, err := client.GetAttestation(context.Background(), &pb.GetAttestationRequest{
		Challenge: challenge,
	})
	if err != nil {
		t.Fatalf("GetAttestation: %v", err)
	}

	// Verify the report binds to the expected public key
	pkResp, _ := client.GetPublicKey(context.Background(), &pb.GetPublicKeyRequest{})
	if err := VerifyDevAttestation(resp.Report, challenge, pkResp.PublicKey); err != nil {
		t.Fatalf("VerifyDevAttestation: %v", err)
	}

	// Full verification with key (only possible inside enclave, but we have it in test)
	skBytes := sk.Key.Bytes()
	if err := VerifyDevAttestationWithKey(resp.Report, challenge, skBytes[:]); err != nil {
		t.Fatalf("VerifyDevAttestationWithKey: %v", err)
	}
}

// TestAttestationDisabledByDefault checks that a server started with
// AttestNone refuses GetAttestation — so an operator who forgot to opt
// into dev attestation can't accidentally hand out HMAC reports.
func TestAttestationDisabledByDefault(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	srv := NewServerFromKey(sk, AttestNone)

	_, err := srv.GetAttestation(context.Background(), &pb.GetAttestationRequest{
		Challenge: make([]byte, 32),
	})
	if err == nil {
		t.Fatal("expected GetAttestation to fail with AttestNone")
	}
	if got := status.Code(err); got != codes.FailedPrecondition {
		t.Fatalf("status code = %v, want FailedPrecondition", got)
	}
}
