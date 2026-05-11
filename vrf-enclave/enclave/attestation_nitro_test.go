package enclave

import (
	"bytes"
	"context"
	"crypto/rand"
	"strings"
	"testing"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"

	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

func TestNitroMockRoundtrip(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()

	challenge := make([]byte, 32)
	rand.Read(challenge)

	report, err := CreateMockNitroAttestation(skBytes[:], pk, challenge)
	if err != nil {
		t.Fatalf("CreateMockNitroAttestation: %v", err)
	}

	doc, err := VerifyNitroAttestation(report, VerifyNitroAttestationOptions{
		AllowDev:          true,
		ExpectedPublicKey: pk,
		ExpectedNonce:     challenge,
		ExpectedPCRs:      allZeroNitroPCRs(),
	})
	if err != nil {
		t.Fatalf("VerifyNitroAttestation: %v", err)
	}
	if !bytes.Equal(doc.PublicKey, pk) {
		t.Fatalf("doc.PublicKey mismatch")
	}
}

func TestNitroVerifierRejectsDevSignatureWhenAllowDevFalse(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()
	challenge := make([]byte, 32)
	rand.Read(challenge)

	report, err := CreateMockNitroAttestation(skBytes[:], pk, challenge)
	if err != nil {
		t.Fatalf("CreateMockNitroAttestation: %v", err)
	}
	_, err = VerifyNitroAttestation(report, VerifyNitroAttestationOptions{
		AllowDev:          false,
		ExpectedPublicKey: pk,
		ExpectedNonce:     challenge,
	})
	if err == nil || !strings.Contains(err.Error(), "dev-signed attestation rejected") {
		t.Fatalf("expected rejection without AllowDev, got %v", err)
	}
}

func TestNitroVerifierRejectsPublicKeyMismatch(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()
	challenge := make([]byte, 32)
	rand.Read(challenge)

	report, _ := CreateMockNitroAttestation(skBytes[:], pk, challenge)

	other, _ := secp256k1.GeneratePrivateKey()
	_, err := VerifyNitroAttestation(report, VerifyNitroAttestationOptions{
		AllowDev:          true,
		ExpectedPublicKey: other.PubKey().SerializeCompressed(),
		ExpectedNonce:     challenge,
	})
	if err == nil || !strings.Contains(err.Error(), "public_key does not match") {
		t.Fatalf("expected public key mismatch, got %v", err)
	}
}

func TestNitroVerifierRejectsPCRMismatch(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()
	challenge := make([]byte, 32)
	rand.Read(challenge)

	report, _ := CreateMockNitroAttestation(skBytes[:], pk, challenge)

	bad := make([]byte, 48)
	bad[0] = 0xff
	_, err := VerifyNitroAttestation(report, VerifyNitroAttestationOptions{
		AllowDev:          true,
		ExpectedPublicKey: pk,
		ExpectedNonce:     challenge,
		ExpectedPCRs:      map[uint8][]byte{0: bad},
	})
	if err == nil || !strings.Contains(err.Error(), "PCR0 mismatch") {
		t.Fatalf("expected PCR0 mismatch, got %v", err)
	}
}

func TestNitroVerifierRejectsTamperedSignature(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	pk := sk.PubKey().SerializeCompressed()
	skBytes := sk.Key.Bytes()
	challenge := make([]byte, 32)
	rand.Read(challenge)

	report, _ := CreateMockNitroAttestation(skBytes[:], pk, challenge)
	// Flip a byte near the end (signature region).
	report[len(report)-2] ^= 0x01

	_, err := VerifyNitroAttestation(report, VerifyNitroAttestationOptions{
		AllowDev:          true,
		ExpectedPublicKey: pk,
		ExpectedNonce:     challenge,
	})
	if err == nil {
		t.Fatal("expected tampered nitro-mock report to fail verification")
	}
}

func TestNitroAttestationOverGRPC(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	srv := NewServerFromKey(sk, AttestNitroMock)

	conn, client := startTestGRPCClient(t, srv)
	defer conn.Close()

	challenge := make([]byte, 32)
	rand.Read(challenge)
	resp, err := client.GetAttestation(context.Background(), &pb.GetAttestationRequest{Challenge: challenge})
	if err != nil {
		t.Fatalf("GetAttestation: %v", err)
	}
	pkResp, _ := client.GetPublicKey(context.Background(), &pb.GetPublicKeyRequest{})
	if _, err := VerifyNitroAttestation(resp.Report, VerifyNitroAttestationOptions{
		AllowDev:          true,
		ExpectedPublicKey: pkResp.PublicKey,
		ExpectedNonce:     challenge,
		ExpectedPCRs:      allZeroNitroPCRs(),
	}); err != nil {
		t.Fatalf("verify nitro-mock attestation: %v", err)
	}
}

func TestNitroAttestationDisabledOnNitroMode(t *testing.T) {
	sk, _ := secp256k1.GeneratePrivateKey()
	srv := NewServerFromKey(sk, AttestNitro)

	_, err := srv.GetAttestation(context.Background(), &pb.GetAttestationRequest{Challenge: make([]byte, 32)})
	if err == nil {
		t.Fatal("expected AttestNitro stub to return an error")
	}
	if !strings.Contains(err.Error(), "NSM bridge") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func allZeroNitroPCRs() map[uint8][]byte {
	out := map[uint8][]byte{}
	for _, idx := range []uint8{0, 1, 2, 8} {
		out[idx] = make([]byte, 48)
	}
	return out
}
