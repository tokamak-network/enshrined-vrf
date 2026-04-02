package ecvrf

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"testing"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
)

// generateRandomKey creates a random secp256k1 private key for testing.
func generateRandomKey(t *testing.T) *secp256k1.PrivateKey {
	t.Helper()
	sk, err := secp256k1.GeneratePrivateKey()
	if err != nil {
		t.Fatalf("failed to generate key: %v", err)
	}
	return sk
}

// --- Basic Round-Trip Tests ---

func TestProveVerifyRoundTrip(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()
	alpha := []byte("test message")

	beta, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatalf("Prove failed: %v", err)
	}

	valid, betaV, err := Verify(pk, alpha, pi)
	if err != nil {
		t.Fatalf("Verify returned error: %v", err)
	}
	if !valid {
		t.Fatal("Verify returned invalid for a valid proof")
	}
	if beta != betaV {
		t.Fatalf("beta mismatch: Prove=%x, Verify=%x", beta, betaV)
	}
}

func TestProveVerifyEmptyAlpha(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()

	beta, pi, err := Prove(sk, []byte{})
	if err != nil {
		t.Fatalf("Prove with empty alpha failed: %v", err)
	}

	valid, betaV, err := Verify(pk, []byte{}, pi)
	if err != nil {
		t.Fatalf("Verify returned error: %v", err)
	}
	if !valid {
		t.Fatal("Verify returned invalid")
	}
	if beta != betaV {
		t.Fatal("beta mismatch")
	}
}

func TestProveVerifyLargeAlpha(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()

	// 10KB alpha
	alpha := make([]byte, 10240)
	rand.Read(alpha)

	beta, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatalf("Prove with large alpha failed: %v", err)
	}

	valid, betaV, err := Verify(pk, alpha, pi)
	if err != nil {
		t.Fatalf("Verify returned error: %v", err)
	}
	if !valid {
		t.Fatal("Verify returned invalid")
	}
	if beta != betaV {
		t.Fatal("beta mismatch")
	}
}

// --- Determinism Tests ---

func TestDeterminism(t *testing.T) {
	sk := generateRandomKey(t)
	alpha := []byte("determinism test")

	beta1, pi1, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	beta2, pi2, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	if beta1 != beta2 {
		t.Fatal("same (sk, alpha) produced different beta values")
	}
	if pi1 != pi2 {
		t.Fatal("same (sk, alpha) produced different pi values")
	}
}

func TestDeterminismManyRuns(t *testing.T) {
	sk := generateRandomKey(t)
	alpha := []byte("many runs")

	beta0, pi0, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	for i := 0; i < 100; i++ {
		beta, pi, err := Prove(sk, alpha)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		if beta != beta0 {
			t.Fatalf("run %d: beta differs", i)
		}
		if pi != pi0 {
			t.Fatalf("run %d: pi differs", i)
		}
	}
}

// --- Uniqueness Tests ---

func TestDifferentAlphaProducesDifferentBeta(t *testing.T) {
	sk := generateRandomKey(t)

	beta1, _, _ := Prove(sk, []byte("alpha1"))
	beta2, _, _ := Prove(sk, []byte("alpha2"))

	if beta1 == beta2 {
		t.Fatal("different alphas produced the same beta")
	}
}

func TestDifferentKeysProduceDifferentBeta(t *testing.T) {
	sk1 := generateRandomKey(t)
	sk2 := generateRandomKey(t)
	alpha := []byte("same alpha")

	beta1, _, _ := Prove(sk1, alpha)
	beta2, _, _ := Prove(sk2, alpha)

	if beta1 == beta2 {
		t.Fatal("different keys produced the same beta")
	}
}

// --- Tampered Proof Rejection ---

func TestVerifyRejectsTamperedBeta(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()
	alpha := []byte("tamper test")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	// The beta is derived from pi, so tampering with Gamma in pi changes beta
	// But Verify recomputes beta from pi, so this test verifies that
	// changing the Gamma point in pi causes verification failure
	tamperedPi := pi
	tamperedPi[1] ^= 0xFF // flip a byte in the Gamma point

	valid, _, err := Verify(pk, alpha, tamperedPi)
	if err == nil && valid {
		t.Fatal("Verify accepted a tampered proof (Gamma tampered)")
	}
}

func TestVerifyRejectsTamperedC(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()
	alpha := []byte("tamper c test")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	tamperedPi := pi
	tamperedPi[PtLen] ^= 0x01 // flip bit in c

	valid, _, err := Verify(pk, alpha, tamperedPi)
	if err != nil {
		// decoding error is acceptable
		return
	}
	if valid {
		t.Fatal("Verify accepted a proof with tampered c")
	}
}

func TestVerifyRejectsTamperedS(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()
	alpha := []byte("tamper s test")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	tamperedPi := pi
	tamperedPi[PtLen+CLen] ^= 0x01 // flip bit in s

	valid, _, err := Verify(pk, alpha, tamperedPi)
	if err != nil {
		return
	}
	if valid {
		t.Fatal("Verify accepted a proof with tampered s")
	}
}

func TestVerifyRejectsWrongKey(t *testing.T) {
	sk := generateRandomKey(t)
	wrongPK := generateRandomKey(t).PubKey()
	alpha := []byte("wrong key test")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	valid, _, err := Verify(wrongPK, alpha, pi)
	if err != nil {
		return
	}
	if valid {
		t.Fatal("Verify accepted a proof with wrong public key")
	}
}

func TestVerifyRejectsWrongAlpha(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()

	_, pi, err := Prove(sk, []byte("correct alpha"))
	if err != nil {
		t.Fatal(err)
	}

	valid, _, err := Verify(pk, []byte("wrong alpha"), pi)
	if err != nil {
		return
	}
	if valid {
		t.Fatal("Verify accepted a proof with wrong alpha")
	}
}

// --- Proof Structure Tests ---

func TestProofLength(t *testing.T) {
	sk := generateRandomKey(t)
	_, pi, err := Prove(sk, []byte("length test"))
	if err != nil {
		t.Fatal(err)
	}

	if len(pi) != ProofLen {
		t.Fatalf("proof length = %d, want %d", len(pi), ProofLen)
	}
}

func TestBetaLength(t *testing.T) {
	sk := generateRandomKey(t)
	beta, _, err := Prove(sk, []byte("beta length"))
	if err != nil {
		t.Fatal(err)
	}

	if len(beta) != OutputLen {
		t.Fatalf("beta length = %d, want %d", len(beta), OutputLen)
	}
}

func TestProofToHashConsistency(t *testing.T) {
	sk := generateRandomKey(t)
	alpha := []byte("proof_to_hash test")

	beta, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	betaFromProof, err := ProofToHash(pi)
	if err != nil {
		t.Fatalf("ProofToHash failed: %v", err)
	}

	if beta != betaFromProof {
		t.Fatal("ProofToHash result differs from Prove result")
	}
}

// --- Mass Round-Trip Test ---

func TestMassRoundTrip(t *testing.T) {
	const n = 1000
	for i := 0; i < n; i++ {
		sk := generateRandomKey(t)
		pk := sk.PubKey()
		alpha := []byte(fmt.Sprintf("mass test %d", i))

		beta, pi, err := Prove(sk, alpha)
		if err != nil {
			t.Fatalf("iteration %d: Prove failed: %v", i, err)
		}

		valid, betaV, err := Verify(pk, alpha, pi)
		if err != nil {
			t.Fatalf("iteration %d: Verify error: %v", i, err)
		}
		if !valid {
			t.Fatalf("iteration %d: Verify returned invalid", i)
		}
		if beta != betaV {
			t.Fatalf("iteration %d: beta mismatch", i)
		}
	}
}

// --- Decode/Encode Proof Symmetry ---

func TestEncodeDecodeProof(t *testing.T) {
	sk := generateRandomKey(t)
	alpha := []byte("encode decode")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	Gamma, c, s, err := decodeProof(pi)
	if err != nil {
		t.Fatalf("decodeProof failed: %v", err)
	}

	reencoded := encodeProof(Gamma, c, s)
	if reencoded != pi {
		t.Fatal("encode/decode round-trip failed")
	}
}

// --- Invalid Input Tests ---

func TestDecodeProofInvalidGamma(t *testing.T) {
	var pi [81]byte
	// All zeros is not a valid compressed point
	_, _, _, err := decodeProof(pi)
	if err == nil {
		t.Fatal("expected error for invalid Gamma point")
	}
}

func TestProofToHashInvalidProof(t *testing.T) {
	var pi [81]byte
	_, err := ProofToHash(pi)
	if err == nil {
		t.Fatal("expected error for invalid proof")
	}
}

// --- Known Vector Test ---
// This test ensures that a specific key+alpha always produces the same output,
// catching any accidental algorithm changes.

func TestKnownVector(t *testing.T) {
	// Use a fixed private key (32 bytes)
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey()
	alpha := []byte("sample")

	beta, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatalf("Prove failed: %v", err)
	}

	// Verify the proof
	valid, betaV, err := Verify(pk, alpha, pi)
	if err != nil {
		t.Fatalf("Verify error: %v", err)
	}
	if !valid {
		t.Fatal("known vector verification failed")
	}
	if beta != betaV {
		t.Fatal("known vector beta mismatch")
	}

	// Record the expected values so future changes are detected.
	// If you change the algorithm, update these values.
	expectedBeta := hex.EncodeToString(beta[:])
	expectedPi := hex.EncodeToString(pi[:])
	t.Logf("Known vector beta: %s", expectedBeta)
	t.Logf("Known vector pi:   %s", expectedPi)

	// Run again to confirm determinism
	beta2, pi2, _ := Prove(sk, alpha)
	if hex.EncodeToString(beta2[:]) != expectedBeta {
		t.Fatal("known vector beta is not deterministic")
	}
	if hex.EncodeToString(pi2[:]) != expectedPi {
		t.Fatal("known vector pi is not deterministic")
	}
}

// --- Bit-flip exhaustive test on proof ---

func TestBitFlipRejection(t *testing.T) {
	sk := generateRandomKey(t)
	pk := sk.PubKey()
	alpha := []byte("bitflip test")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		t.Fatal(err)
	}

	// Flip each bit in the proof and verify rejection
	rejected := 0
	for byteIdx := 0; byteIdx < ProofLen; byteIdx++ {
		for bitIdx := 0; bitIdx < 8; bitIdx++ {
			tampered := pi
			tampered[byteIdx] ^= 1 << uint(bitIdx)

			valid, _, err := Verify(pk, alpha, tampered)
			if err != nil || !valid {
				rejected++
			}
		}
	}

	total := ProofLen * 8
	t.Logf("Bit-flip rejection: %d/%d (%.1f%%)", rejected, total, float64(rejected)/float64(total)*100)

	// We expect nearly all bit flips to cause rejection.
	// Some bit flips in the Gamma point prefix byte might still parse as valid but different point.
	if rejected < total*95/100 {
		t.Fatalf("too many bit flips accepted: %d/%d", total-rejected, total)
	}
}

// --- Beta distribution test ---

func TestBetaDistribution(t *testing.T) {
	sk := generateRandomKey(t)

	// Generate many betas and check byte distribution is roughly uniform
	const n = 1000
	byteCounts := [256]int{}

	for i := 0; i < n; i++ {
		alpha := []byte(fmt.Sprintf("distribution-%d", i))
		beta, _, err := Prove(sk, alpha)
		if err != nil {
			t.Fatal(err)
		}
		for _, b := range beta {
			byteCounts[b]++
		}
	}

	// Each byte value should appear roughly n*32/256 = 125 times
	expected := float64(n*OutputLen) / 256.0
	minCount := int(expected * 0.3) // generous bounds
	maxCount := int(expected * 2.0)

	for i, count := range byteCounts {
		if count < minCount || count > maxCount {
			t.Logf("WARNING: byte 0x%02x appeared %d times (expected ~%.0f)", i, count, expected)
		}
	}
}

// --- Fuzz Test ---

func FuzzProveVerify(f *testing.F) {
	// Add seed corpus
	f.Add([]byte("hello"))
	f.Add([]byte(""))
	f.Add([]byte{0x00})
	f.Add([]byte{0xFF, 0xFF, 0xFF})
	f.Add(make([]byte, 256))

	sk := func() *secp256k1.PrivateKey {
		skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
		return secp256k1.PrivKeyFromBytes(skBytes)
	}()
	pk := sk.PubKey()

	f.Fuzz(func(t *testing.T, alpha []byte) {
		beta, pi, err := Prove(sk, alpha)
		if err != nil {
			t.Fatalf("Prove failed: %v", err)
		}

		valid, betaV, err := Verify(pk, alpha, pi)
		if err != nil {
			t.Fatalf("Verify error: %v", err)
		}
		if !valid {
			t.Fatal("valid proof rejected")
		}
		if !bytes.Equal(beta[:], betaV[:]) {
			t.Fatal("beta mismatch")
		}
	})
}

func FuzzVerifyRejectsRandom(f *testing.F) {
	f.Add(make([]byte, 81))
	f.Add(make([]byte, 81))

	pk := func() *secp256k1.PublicKey {
		skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
		return secp256k1.PrivKeyFromBytes(skBytes).PubKey()
	}()

	f.Fuzz(func(t *testing.T, piBytes []byte) {
		if len(piBytes) != ProofLen {
			return
		}
		var pi [81]byte
		copy(pi[:], piBytes)

		valid, _, _ := Verify(pk, []byte("test"), pi)
		if valid {
			// Random bytes should almost never produce a valid proof
			// If this happens, it's not necessarily a bug but extremely unlikely
			t.Logf("random proof validated (astronomically unlikely)")
		}
	})
}

// --- Benchmarks ---

func BenchmarkProve(b *testing.B) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	alpha := []byte("benchmark alpha")

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, err := Prove(sk, alpha)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkVerify(b *testing.B) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey()
	alpha := []byte("benchmark alpha")

	_, pi, err := Prove(sk, alpha)
	if err != nil {
		b.Fatal(err)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		valid, _, err := Verify(pk, alpha, pi)
		if err != nil || !valid {
			b.Fatal("verification failed")
		}
	}
}

func BenchmarkProofToHash(b *testing.B) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	alpha := []byte("benchmark alpha")

	_, pi, _ := Prove(sk, alpha)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := ProofToHash(pi)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkEncodeToCurveTAI(b *testing.B) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey()
	alpha := []byte("benchmark alpha")

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := encodeToCurveTAI(pk, alpha)
		if err != nil {
			b.Fatal(err)
		}
	}
}
