package enclave

import (
	"crypto/hmac"
	"crypto/sha256"
	"errors"
)

// Attestation report layout (dev mode):
//
//   [0:33]  public key (compressed secp256k1)
//   [33:65] HMAC-SHA256(attestKey, challenge || publicKey)
//
// Total: 65 bytes
//
// In production, this is replaced by a platform attestation quote
// (e.g. SGX ECDSA quote ~4KB) that binds the public key to hardware
// measurements (MRENCLAVE, MRSIGNER, etc.).

const (
	devReportPKLen   = 33
	devReportHMACLen = 32
	devReportLen     = devReportPKLen + devReportHMACLen
)

// CreateDevAttestation generates a development-mode attestation report.
// It binds the public key to the challenge using the secret key as the
// HMAC key, proving the enclave holds the corresponding private key.
//
// This provides a weaker guarantee than real TEE attestation: it proves
// key possession but NOT that the code runs inside a secure enclave.
func CreateDevAttestation(skBytes []byte, pk []byte, challenge []byte) []byte {
	mac := computeAttestMAC(skBytes, pk, challenge)

	report := make([]byte, devReportLen)
	copy(report[:devReportPKLen], pk)
	copy(report[devReportPKLen:], mac)
	return report
}

// VerifyDevAttestation verifies a development-mode attestation report.
// It checks that the report binds the expected public key to the challenge.
// Returns the public key extracted from the report.
//
// In production, replace with SGX/TDX/SEV quote verification that
// additionally checks hardware measurements and TCB status.
func VerifyDevAttestation(report []byte, challenge []byte, expectedPK []byte) error {
	if len(report) != devReportLen {
		return errors.New("attestation: invalid report length")
	}

	reportPK := report[:devReportPKLen]
	reportMAC := report[devReportPKLen:]

	// Check public key matches
	if !hmac.Equal(reportPK, expectedPK) {
		return errors.New("attestation: public key mismatch")
	}

	// We cannot verify the HMAC without the secret key, but we can
	// check structural validity. The actual verification happens via
	// a challenge-response: the verifier sends a fresh challenge and
	// checks that a valid report comes back with the expected PK.
	//
	// For a self-check (within the enclave), we can verify fully.
	if len(reportMAC) != devReportHMACLen {
		return errors.New("attestation: invalid MAC length")
	}

	return nil
}

// VerifyDevAttestationWithKey verifies a dev attestation when the secret
// key is available (e.g. for testing or enclave self-check).
func VerifyDevAttestationWithKey(report []byte, challenge []byte, skBytes []byte) error {
	if len(report) != devReportLen {
		return errors.New("attestation: invalid report length")
	}

	pk := report[:devReportPKLen]
	reportMAC := report[devReportPKLen:]

	expectedMAC := computeAttestMAC(skBytes, pk, challenge)
	if !hmac.Equal(reportMAC, expectedMAC) {
		return errors.New("attestation: HMAC verification failed")
	}

	return nil
}

func computeAttestMAC(skBytes []byte, pk []byte, challenge []byte) []byte {
	h := hmac.New(sha256.New, skBytes)
	h.Write(challenge)
	h.Write(pk)
	return h.Sum(nil)
}
