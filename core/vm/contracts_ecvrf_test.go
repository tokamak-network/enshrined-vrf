package vm

import (
	"bytes"
	"encoding/hex"
	"testing"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/crypto/ecvrf"
)

// proofAndInput runs Prove for (sk, alpha) and returns the 178-byte
// precompile input (pk || alpha || beta || pi).
func proofAndInput(t *testing.T, sk *secp256k1.PrivateKey, alpha []byte) (input, beta, pi []byte) {
	t.Helper()
	if len(alpha) != 32 {
		t.Fatalf("alpha must be 32 bytes, got %d", len(alpha))
	}
	b, p, err := ecvrf.Prove(sk, alpha)
	if err != nil {
		t.Fatalf("ecvrf.Prove: %v", err)
	}
	pk := sk.PubKey().SerializeCompressed()
	in := make([]byte, 0, 33+32+32+81)
	in = append(in, pk...)
	in = append(in, alpha...)
	in = append(in, b[:]...)
	in = append(in, p[:]...)
	return in, b[:], p[:]
}

// TestECVRFPrecompileAcceptsProverOutput checks that proofs produced by the
// ecvrf.Prove path (what the enclave and LocalVRFProver use) are accepted by
// the precompile. This is the cross-boundary contract: if it ever fails,
// every committed VRF output becomes unverifiable on L2.
func TestECVRFPrecompileAcceptsProverOutput(t *testing.T) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)

	alphas := [][]byte{
		bytes.Repeat([]byte{0x00}, 32),
		bytes.Repeat([]byte{0xff}, 32),
		func() []byte {
			var b [32]byte
			for i := range b {
				b[i] = byte(i)
			}
			return b[:]
		}(),
	}

	pc := &ecvrfVerify{}
	for i, alpha := range alphas {
		input, _, _ := proofAndInput(t, sk, alpha)
		out, err := pc.Run(input)
		if err != nil {
			t.Fatalf("case %d: Run returned error: %v", i, err)
		}
		if !bytes.Equal(out, []byte{0x01}) {
			t.Fatalf("case %d: expected 0x01, got %x", i, out)
		}
	}
}

func TestECVRFPrecompileRejectsTamperedInputs(t *testing.T) {
	skBytes, _ := hex.DecodeString("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	var alpha [32]byte
	alpha[0] = 0x42
	validInput, _, _ := proofAndInput(t, sk, alpha[:])

	pc := &ecvrfVerify{}

	tamper := func(name string, mutate func([]byte)) {
		t.Run(name, func(t *testing.T) {
			in := append([]byte(nil), validInput...)
			mutate(in)
			out, err := pc.Run(in)
			if err != nil {
				t.Fatalf("Run returned error: %v", err)
			}
			if bytes.Equal(out, []byte{0x01}) {
				t.Fatalf("expected rejection, got 0x01")
			}
		})
	}

	tamper("flip_alpha_bit", func(b []byte) { b[33] ^= 0x01 })
	tamper("flip_beta_bit", func(b []byte) { b[65] ^= 0x01 })
	tamper("flip_pi_c_bit", func(b []byte) { b[97+33] ^= 0x01 })    // c region in pi
	tamper("flip_pi_s_bit", func(b []byte) { b[97+33+16] ^= 0x01 }) // s region in pi

	t.Run("wrong_length", func(t *testing.T) {
		out, err := pc.Run(validInput[:len(validInput)-1])
		if err != nil || out != nil {
			t.Fatalf("short input should return (nil,nil), got (%x,%v)", out, err)
		}
	})

	t.Run("wrong_public_key", func(t *testing.T) {
		otherSk, _ := secp256k1.GeneratePrivateKey()
		in := append([]byte(nil), validInput...)
		copy(in[:33], otherSk.PubKey().SerializeCompressed())
		out, err := pc.Run(in)
		if err != nil {
			t.Fatalf("Run error: %v", err)
		}
		if bytes.Equal(out, []byte{0x01}) {
			t.Fatal("expected rejection for wrong pk")
		}
	})
}
