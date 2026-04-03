package vm

import (
	"encoding/hex"
	"testing"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

func makeValidInput(t *testing.T) ([]byte, *secp256k1.PrivateKey) {
	t.Helper()
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey()
	alpha := make([]byte, 32)
	copy(alpha, []byte("precompile test alpha"))

	beta, pi, err := ecvrf.Prove(sk, alpha)
	if err != nil {
		t.Fatalf("Prove failed: %v", err)
	}

	// Build input: pk(33) || alpha(32) || beta(32) || pi(81)
	input := make([]byte, 0, 178)
	input = append(input, pk.SerializeCompressed()...)
	input = append(input, alpha...)
	input = append(input, beta[:]...)
	input = append(input, pi[:]...)

	return input, sk
}

func TestEcvrfVerifyValid(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	gas := c.RequiredGas(input)
	if gas != EcvrfVerifyGas {
		t.Fatalf("gas = %d, want %d", gas, EcvrfVerifyGas)
	}

	output, err := c.Run(input)
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}

	if len(output) != 1 || output[0] != 0x01 {
		t.Fatalf("expected valid (0x01), got %x", output)
	}
}

func TestEcvrfVerifyInvalidInputLength(t *testing.T) {
	c := &EcvrfVerify{}

	testCases := []struct {
		name string
		len  int
	}{
		{"empty", 0},
		{"too short", 100},
		{"one byte short", 177},
		{"one byte long", 179},
		{"way too long", 256},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			input := make([]byte, tc.len)
			_, err := c.Run(input)
			if err == nil {
				t.Fatalf("expected error for input length %d", tc.len)
			}
		})
	}
}

func TestEcvrfVerifyInvalidPubKey(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	// Corrupt the public key
	corrupted := make([]byte, len(input))
	copy(corrupted, input)
	corrupted[0] = 0x05 // invalid prefix

	output, err := c.Run(corrupted)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if output[0] != 0x00 {
		t.Fatal("expected invalid for corrupted pubkey")
	}
}

func TestEcvrfVerifyWrongPubKey(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	// Use a different public key
	wrongSK, _ := secp256k1.GeneratePrivateKey()
	wrongPK := wrongSK.PubKey()

	corrupted := make([]byte, len(input))
	copy(corrupted, input)
	copy(corrupted[0:33], wrongPK.SerializeCompressed())

	output, err := c.Run(corrupted)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if output[0] != 0x00 {
		t.Fatal("expected invalid for wrong pubkey")
	}
}

func TestEcvrfVerifyTamperedAlpha(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	corrupted := make([]byte, len(input))
	copy(corrupted, input)
	corrupted[33] ^= 0xFF // flip byte in alpha

	output, err := c.Run(corrupted)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if output[0] != 0x00 {
		t.Fatal("expected invalid for tampered alpha")
	}
}

func TestEcvrfVerifyTamperedBeta(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	corrupted := make([]byte, len(input))
	copy(corrupted, input)
	corrupted[65] ^= 0xFF // flip byte in beta

	output, err := c.Run(corrupted)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if output[0] != 0x00 {
		t.Fatal("expected invalid for tampered beta")
	}
}

func TestEcvrfVerifyTamperedProof(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	corrupted := make([]byte, len(input))
	copy(corrupted, input)
	corrupted[97+1] ^= 0xFF // flip byte in pi (Gamma)

	output, err := c.Run(corrupted)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if output[0] != 0x00 {
		t.Fatal("expected invalid for tampered proof")
	}
}

func TestEcvrfVerifyBetaMismatch(t *testing.T) {
	// Valid proof but beta field doesn't match the actual VRF output
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey()
	alpha := make([]byte, 32)
	copy(alpha, []byte("beta mismatch"))

	_, pi, err := ecvrf.Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	// Use a fake beta (all zeros)
	fakeBeta := make([]byte, 32)

	input := make([]byte, 0, 178)
	input = append(input, pk.SerializeCompressed()...)
	input = append(input, alpha...)
	input = append(input, fakeBeta...)
	input = append(input, pi[:]...)

	c := &EcvrfVerify{}
	output, err := c.Run(input)
	if err != nil {
		t.Fatal(err)
	}
	if output[0] != 0x00 {
		t.Fatal("expected invalid for mismatched beta")
	}
}

func TestEcvrfVerifyDeterministic(t *testing.T) {
	input, _ := makeValidInput(t)
	c := &EcvrfVerify{}

	for i := 0; i < 100; i++ {
		output, err := c.Run(input)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		if output[0] != 0x01 {
			t.Fatalf("run %d: expected valid", i)
		}
	}
}

func BenchmarkEcvrfVerifyPrecompile(b *testing.B) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey()
	alpha := make([]byte, 32)
	copy(alpha, []byte("benchmark"))

	beta, pi, _ := ecvrf.Prove(sk, alpha)

	input := make([]byte, 0, 178)
	input = append(input, pk.SerializeCompressed()...)
	input = append(input, alpha...)
	input = append(input, beta[:]...)
	input = append(input, pi[:]...)

	c := &EcvrfVerify{}
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		output, err := c.Run(input)
		if err != nil || output[0] != 0x01 {
			b.Fatal("verification failed")
		}
	}
}
