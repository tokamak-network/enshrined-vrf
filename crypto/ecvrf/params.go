// Package ecvrf implements ECVRF-SECP256K1-SHA256-TAI as specified in RFC 9381,
// adapted for the secp256k1 elliptic curve.
//
// This is a custom suite (suite_string = 0xFE) following the RFC 9381 framework
// with secp256k1 as the EC group and SHA-256 as the hash function.
package ecvrf

const (
	// SuiteString identifies this custom ECVRF suite (outside RFC-defined range).
	SuiteString byte = 0xFE

	// PtLen is the length of a compressed SEC1 point on secp256k1.
	PtLen = 33

	// CLen is the challenge length (truncated hash output for the Schnorr challenge).
	CLen = 16

	// QLen is the byte length of the curve order (32 bytes for secp256k1).
	QLen = 32

	// ProofLen is the total proof size: Gamma (compressed point) + c + s.
	ProofLen = PtLen + CLen + QLen // 81

	// OutputLen is the VRF output (beta) size in bytes.
	OutputLen = 32
)
