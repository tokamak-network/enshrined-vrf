package enclave

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/decred/dcrd/dcrec/secp256k1/v4/ecdsa"
	"github.com/fxamacker/cbor/v2"
)

// AWS Nitro attestation document layout.
//
// Real Nitro Enclaves return a COSE_Sign1 (RFC 8152) wrapping a
// CBOR-encoded NitroAttestationDoc, signed by the enclave's NSM module
// with a key chained to the AWS Nitro root CA. We never have access to
// that signing key off-EC2.
//
// nitro-mock signs the SAME CBOR doc shape with the enclave's own
// secp256k1 key under a custom COSE algorithm id (devNitroCOSEAlg). This
// lets the off-platform verifier path be exercised on macOS and CI
// runners without an EC2 Nitro environment. The verifier rejects this
// signature unless AllowDev is true.

// COSE algorithm identifier for the dev/mock signature path. Real Nitro
// uses ES384 (-35); this id is intentionally unused by IANA and is the
// only algorithm the verifier accepts when AllowDev=true.
const devNitroCOSEAlg = -65535

// COSE_Sign1 CBOR tag (RFC 8152 §2).
const coseSign1Tag = 18

// NitroAttestationDoc is the inner payload of the COSE_Sign1 envelope.
// Field tags match the AWS Nitro Enclaves attestation document schema
// (https://docs.aws.amazon.com/enclaves/latest/user/verify-root.html).
type NitroAttestationDoc struct {
	ModuleID    string           `cbor:"module_id"`
	Digest      string           `cbor:"digest"`
	Timestamp   uint64           `cbor:"timestamp"`
	PCRs        map[uint8][]byte `cbor:"pcrs"`
	Certificate []byte           `cbor:"certificate"`
	CABundle    [][]byte         `cbor:"cabundle"`
	PublicKey   []byte           `cbor:"public_key,omitempty"`
	UserData    []byte           `cbor:"user_data,omitempty"`
	Nonce       []byte           `cbor:"nonce,omitempty"`
}

// CreateMockNitroAttestation produces a Nitro-shaped COSE_Sign1
// attestation document signed with the supplied secp256k1 key. The PCR
// map is filled with all-zero 48-byte values matching the AWS Nitro
// Enclaves PCR0..PCR8 layout. Verifiers must treat this document as
// dev-only — it is not chained to AWS Nitro root CA.
func CreateMockNitroAttestation(skBytes []byte, pk []byte, challenge []byte) ([]byte, error) {
	if len(pk) != 33 {
		return nil, fmt.Errorf("nitro: public key must be 33 bytes, got %d", len(pk))
	}
	if len(skBytes) != 32 {
		return nil, fmt.Errorf("nitro: secret key must be 32 bytes, got %d", len(skBytes))
	}
	doc := NitroAttestationDoc{
		ModuleID:  "i-mock-vrf-enclave",
		Digest:    "SHA384",
		Timestamp: uint64(time.Now().UnixMilli()),
		PCRs: map[uint8][]byte{
			0: make([]byte, 48),
			1: make([]byte, 48),
			2: make([]byte, 48),
			3: make([]byte, 48),
			4: make([]byte, 48),
			8: make([]byte, 48),
		},
		Certificate: nil,
		CABundle:    nil,
		PublicKey:   pk,
		UserData:    pk,
		Nonce:       challenge,
	}
	docBytes, err := cborCanonical().Marshal(&doc)
	if err != nil {
		return nil, fmt.Errorf("nitro: marshal doc: %w", err)
	}

	protected, err := cborCanonical().Marshal(map[int]int{1: devNitroCOSEAlg})
	if err != nil {
		return nil, fmt.Errorf("nitro: marshal protected header: %w", err)
	}

	sig, err := signCOSESign1(skBytes, protected, docBytes)
	if err != nil {
		return nil, err
	}

	envelope := []any{protected, map[int]int{}, docBytes, sig}
	tagged := cbor.Tag{Number: coseSign1Tag, Content: envelope}
	out, err := cborCanonical().Marshal(tagged)
	if err != nil {
		return nil, fmt.Errorf("nitro: marshal COSE_Sign1: %w", err)
	}
	return out, nil
}

// VerifyNitroAttestationOptions controls which attestation paths are
// accepted by VerifyNitroAttestation.
type VerifyNitroAttestationOptions struct {
	// AllowDev enables verification of nitro-mock documents signed under
	// the devNitroCOSEAlg algorithm id with a secp256k1 key matching
	// ExpectedPublicKey. Real-platform deployments must leave this false.
	AllowDev bool
	// ExpectedPCRs, when non-empty, requires every (index, value) pair
	// in the attestation doc PCR map to match. PCR indices not present
	// in the map are not checked — supply zero-byte vectors when you
	// want to assert "must be all-zero" for nitro-mock.
	ExpectedPCRs map[uint8][]byte
	// ExpectedPublicKey is matched against the document's public_key
	// field, which the enclave binds to the VRF compressed-SEC1 key.
	ExpectedPublicKey []byte
	// ExpectedNonce, when non-nil, is matched against the document
	// nonce. The enclave returns the request challenge here.
	ExpectedNonce []byte
}

// VerifyNitroAttestation parses a COSE_Sign1-wrapped Nitro attestation
// document, checks that it binds the expected public key (and PCRs and
// nonce when provided), and verifies the signature. Production Nitro
// signatures (chained to AWS Nitro root CA) are not yet implemented in
// this verifier — only the AllowDev path is fully supported.
func VerifyNitroAttestation(report []byte, opts VerifyNitroAttestationOptions) (*NitroAttestationDoc, error) {
	protected, payload, sig, err := unwrapCOSESign1(report)
	if err != nil {
		return nil, err
	}

	alg, err := decodeProtectedAlg(protected)
	if err != nil {
		return nil, err
	}

	var doc NitroAttestationDoc
	if err := cbor.Unmarshal(payload, &doc); err != nil {
		return nil, fmt.Errorf("nitro: parse doc: %w", err)
	}

	if len(opts.ExpectedPublicKey) > 0 {
		if !bytes.Equal(doc.PublicKey, opts.ExpectedPublicKey) {
			return nil, errors.New("nitro: doc public_key does not match expected key")
		}
	}
	if opts.ExpectedNonce != nil {
		if !bytes.Equal(doc.Nonce, opts.ExpectedNonce) {
			return nil, errors.New("nitro: doc nonce does not match challenge")
		}
	}
	for idx, want := range opts.ExpectedPCRs {
		got, ok := doc.PCRs[idx]
		if !ok {
			return nil, fmt.Errorf("nitro: missing PCR%d in attestation doc", idx)
		}
		if !bytes.Equal(got, want) {
			return nil, fmt.Errorf("nitro: PCR%d mismatch", idx)
		}
	}

	switch alg {
	case devNitroCOSEAlg:
		if !opts.AllowDev {
			return nil, errors.New("nitro: dev-signed attestation rejected; set AllowDev only for nitro-mock")
		}
		if err := verifyCOSESign1Dev(doc.PublicKey, protected, payload, sig); err != nil {
			return nil, err
		}
	default:
		return nil, fmt.Errorf("nitro: COSE algorithm %d not supported by this verifier (production AWS Nitro chain is pending integration)", alg)
	}

	return &doc, nil
}

// signCOSESign1 builds the COSE_Sign1 SigStructure (RFC 8152 §4.4) and
// signs SHA-256(SigStructure) with the provided secp256k1 key.
func signCOSESign1(skBytes []byte, protected, payload []byte) ([]byte, error) {
	toBeSigned, err := cborCanonical().Marshal([]any{
		"Signature1",
		protected,
		[]byte{}, // external_aad
		payload,
	})
	if err != nil {
		return nil, fmt.Errorf("nitro: marshal SigStructure: %w", err)
	}
	digest := sha256.Sum256(toBeSigned)
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	sig := ecdsa.Sign(sk, digest[:])
	return sig.Serialize(), nil
}

func verifyCOSESign1Dev(pkBytes, protected, payload, sig []byte) error {
	if len(pkBytes) != 33 {
		return fmt.Errorf("nitro: dev verify expects 33-byte SEC1 key, got %d", len(pkBytes))
	}
	pk, err := secp256k1.ParsePubKey(pkBytes)
	if err != nil {
		return fmt.Errorf("nitro: parse dev public key: %w", err)
	}
	parsed, err := ecdsa.ParseDERSignature(sig)
	if err != nil {
		return fmt.Errorf("nitro: parse dev signature: %w", err)
	}
	toBeSigned, err := cborCanonical().Marshal([]any{
		"Signature1",
		protected,
		[]byte{},
		payload,
	})
	if err != nil {
		return fmt.Errorf("nitro: rebuild SigStructure: %w", err)
	}
	digest := sha256.Sum256(toBeSigned)
	if !parsed.Verify(digest[:], pk) {
		return errors.New("nitro: dev signature verification failed")
	}
	return nil
}

func unwrapCOSESign1(report []byte) (protected, payload, sig []byte, err error) {
	var raw cbor.RawMessage
	if err = cbor.Unmarshal(report, &raw); err != nil {
		return nil, nil, nil, fmt.Errorf("nitro: parse outer CBOR: %w", err)
	}
	var tag cbor.Tag
	if tagErr := cbor.Unmarshal(raw, &tag); tagErr == nil && tag.Number == coseSign1Tag {
		envBytes, mErr := cbor.Marshal(tag.Content)
		if mErr != nil {
			return nil, nil, nil, fmt.Errorf("nitro: re-encode tagged envelope: %w", mErr)
		}
		raw = envBytes
	}
	var envelope []cbor.RawMessage
	if err = cbor.Unmarshal(raw, &envelope); err != nil {
		return nil, nil, nil, fmt.Errorf("nitro: parse COSE_Sign1 envelope: %w", err)
	}
	if len(envelope) != 4 {
		return nil, nil, nil, fmt.Errorf("nitro: COSE_Sign1 envelope must have 4 elements, got %d", len(envelope))
	}
	if err = cbor.Unmarshal(envelope[0], &protected); err != nil {
		return nil, nil, nil, fmt.Errorf("nitro: parse protected header: %w", err)
	}
	if err = cbor.Unmarshal(envelope[2], &payload); err != nil {
		return nil, nil, nil, fmt.Errorf("nitro: parse payload: %w", err)
	}
	if err = cbor.Unmarshal(envelope[3], &sig); err != nil {
		return nil, nil, nil, fmt.Errorf("nitro: parse signature: %w", err)
	}
	return protected, payload, sig, nil
}

func decodeProtectedAlg(protected []byte) (int, error) {
	if len(protected) == 0 {
		return 0, errors.New("nitro: protected header is empty")
	}
	hdr := map[int]int{}
	if err := cbor.Unmarshal(protected, &hdr); err != nil {
		return 0, fmt.Errorf("nitro: decode protected header: %w", err)
	}
	alg, ok := hdr[1]
	if !ok {
		return 0, errors.New("nitro: protected header missing alg (label 1)")
	}
	return alg, nil
}

func cborCanonical() cbor.EncMode {
	opts := cbor.CTAP2EncOptions()
	opts.TagsMd = cbor.TagsAllowed
	em, err := opts.EncMode()
	if err != nil {
		// Should never happen — CTAP2EncOptions are static.
		panic(err)
	}
	return em
}
