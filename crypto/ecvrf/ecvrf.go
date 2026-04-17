// Mirror of op-geth/crypto/ecvrf — must stay byte-compatible; the precompile verifies proofs produced here.
package ecvrf

import (
	"crypto/sha256"
	"errors"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
)

var (
	ErrInvalidProof = errors.New("ecvrf: invalid proof")
	ErrProveFailure = errors.New("ecvrf: prove failure")
)

// Prove computes the VRF output (beta) and proof (pi) for the given secret key
// and alpha string, following ECVRF-SECP256K1-SHA256-TAI (RFC 9381 Section 5.1).
func Prove(sk *secp256k1.PrivateKey, alpha []byte) (beta [32]byte, pi [81]byte, err error) {
	// Step 1: Y = sk * G (public key)
	pk := sk.PubKey()

	// Step 2: H = ECVRF_encode_to_curve(suite_string, Y, alpha)
	H, err := encodeToCurveTAI(pk, alpha)
	if err != nil {
		return beta, pi, ErrProveFailure
	}

	// Step 3: Gamma = sk * H
	var HJac, Gamma secp256k1.JacobianPoint
	H.AsJacobian(&HJac)
	secp256k1.ScalarMultNonConst(&sk.Key, &HJac, &Gamma)
	GammaAff := jacobianToPublicKey(&Gamma)

	// Step 4: nonce k = ECVRF_nonce_generation_RFC6979(sk, H)
	hBytes := H.SerializeCompressed()
	hHash := sha256.Sum256(hBytes)
	skBytes := sk.Key.Bytes()
	k := secp256k1.NonceRFC6979(skBytes[:], hHash[:], nil, nil, 0)
	zeroBytes32(&skBytes)

	// Step 5: U = k * G
	var U secp256k1.JacobianPoint
	secp256k1.ScalarBaseMultNonConst(k, &U)

	// Step 6: V = k * H
	var V secp256k1.JacobianPoint
	secp256k1.ScalarMultNonConst(k, &HJac, &V)

	// Step 7: c = ECVRF_challenge_generation(Y, H, Gamma, U, V)
	c := challengeGeneration(pk, H, GammaAff, &U, &V)

	// Step 8: s = (k - c * sk) mod q
	// Using ModNScalar for constant-time arithmetic.
	// ModNScalar has no Sub, so compute: s = k + (-(c * sk))
	var csk secp256k1.ModNScalar
	csk.Set(&c).Mul(&sk.Key)
	csk.Negate()
	var s secp256k1.ModNScalar
	s.Add2(k, &csk)
	k.Zero()

	// Step 9: encode proof
	pi = encodeProof(GammaAff, &c, &s)

	// Step 10: beta = ECVRF_proof_to_hash(pi)
	beta, err = ProofToHash(pi)
	if err != nil {
		return beta, pi, ErrProveFailure
	}

	return beta, pi, nil
}

// Verify checks the VRF proof pi against the public key pk and alpha string,
// following ECVRF-SECP256K1-SHA256-TAI (RFC 9381 Section 5.3).
func Verify(pk *secp256k1.PublicKey, alpha []byte, pi [81]byte) (bool, [32]byte, error) {
	var beta [32]byte

	// Step 1: Decode proof: Gamma, c, s
	Gamma, c, s, err := decodeProof(pi)
	if err != nil {
		return false, beta, err
	}

	// Step 2: H = ECVRF_encode_to_curve(suite_string, Y, alpha)
	H, err := encodeToCurveTAI(pk, alpha)
	if err != nil {
		return false, beta, err
	}

	// Step 3: U = s*G + c*Y
	var sG, cY, U secp256k1.JacobianPoint
	secp256k1.ScalarBaseMultNonConst(s, &sG)
	var pkJac secp256k1.JacobianPoint
	pk.AsJacobian(&pkJac)
	secp256k1.ScalarMultNonConst(c, &pkJac, &cY)
	secp256k1.AddNonConst(&sG, &cY, &U)

	// Step 4: V = s*H + c*Gamma
	var sH, cGamma, V secp256k1.JacobianPoint
	var HJac secp256k1.JacobianPoint
	H.AsJacobian(&HJac)
	secp256k1.ScalarMultNonConst(s, &HJac, &sH)
	var GammaJac secp256k1.JacobianPoint
	Gamma.AsJacobian(&GammaJac)
	secp256k1.ScalarMultNonConst(c, &GammaJac, &cGamma)
	secp256k1.AddNonConst(&sH, &cGamma, &V)

	// Step 5: c' = ECVRF_challenge_generation(Y, H, Gamma, U, V)
	cPrime := challengeGeneration(pk, H, Gamma, &U, &V)

	// Step 6: If c == c', output "VALID" and beta
	if !c.Equals(&cPrime) {
		return false, beta, nil
	}

	beta, err = ProofToHash(pi)
	if err != nil {
		return false, beta, err
	}

	return true, beta, nil
}

// ProofToHash extracts the VRF hash output (beta) from a proof pi,
// following RFC 9381 Section 5.2.
func ProofToHash(pi [81]byte) ([32]byte, error) {
	var beta [32]byte

	Gamma, err := secp256k1.ParsePubKey(pi[:PtLen])
	if err != nil {
		return beta, ErrInvalidProof
	}

	// beta = SHA256(suite_string || 0x03 || point_to_string(cofactor * Gamma) || 0x00)
	// cofactor = 1 for secp256k1
	gammaBytes := Gamma.SerializeCompressed()

	h := sha256.New()
	h.Write([]byte{SuiteString, 0x03})
	h.Write(gammaBytes)
	h.Write([]byte{0x00})
	hash := h.Sum(nil)
	copy(beta[:], hash[:OutputLen])

	return beta, nil
}

// encodeToCurveTAI implements ECVRF_encode_to_curve using try-and-increment (TAI),
// as specified in RFC 9381 Section 5.4.1.1.
func encodeToCurveTAI(pk *secp256k1.PublicKey, alpha []byte) (*secp256k1.PublicKey, error) {
	pkBytes := pk.SerializeCompressed()

	for ctr := byte(0); ctr < 255; ctr++ {
		// hash = SHA256(suite_string || 0x01 || PK || alpha || ctr || 0x00)
		h := sha256.New()
		h.Write([]byte{SuiteString, 0x01})
		h.Write(pkBytes)
		h.Write(alpha)
		h.Write([]byte{ctr, 0x00})
		hash := h.Sum(nil)

		// Try to interpret hash as x-coordinate with 0x02 prefix (even y)
		var candidate [PtLen]byte
		candidate[0] = 0x02
		copy(candidate[1:], hash)

		point, err := secp256k1.ParsePubKey(candidate[:])
		if err != nil {
			continue
		}

		return point, nil
	}

	return nil, errors.New("ecvrf: encode_to_curve failed after 255 attempts")
}

// challengeGeneration implements ECVRF_challenge_generation per RFC 9381 Section 5.4.3.
// Returns the truncated challenge as a ModNScalar (the value fits in CLen=16 bytes).
func challengeGeneration(Y, H, Gamma *secp256k1.PublicKey, U, V *secp256k1.JacobianPoint) secp256k1.ModNScalar {
	UAff := jacobianToPublicKey(U)
	VAff := jacobianToPublicKey(V)

	// c_string = SHA256(suite_string || 0x02 || Y || H || Gamma || U || V || 0x00)
	h := sha256.New()
	h.Write([]byte{SuiteString, 0x02})
	h.Write(Y.SerializeCompressed())
	h.Write(H.SerializeCompressed())
	h.Write(Gamma.SerializeCompressed())
	h.Write(UAff.SerializeCompressed())
	h.Write(VAff.SerializeCompressed())
	h.Write([]byte{0x00})
	hash := h.Sum(nil)

	// Truncate to CLen bytes, then load into a ModNScalar.
	// CLen=16 bytes always fits within the curve order (32 bytes), so
	// SetByteSlice will never reduce mod N.
	var c secp256k1.ModNScalar
	c.SetByteSlice(hash[:CLen])
	return c
}

// encodeProof serializes (Gamma, c, s) into an 81-byte proof.
func encodeProof(Gamma *secp256k1.PublicKey, c, s *secp256k1.ModNScalar) [81]byte {
	var pi [81]byte
	copy(pi[:PtLen], Gamma.SerializeCompressed())

	// c is at most CLen (16) bytes; write zero-padded big-endian into the c field.
	cBytes := c.Bytes()
	copy(pi[PtLen:PtLen+CLen], cBytes[QLen-CLen:])

	// s is a full 32-byte scalar.
	sBytes := s.Bytes()
	copy(pi[PtLen+CLen:], sBytes[:])

	return pi
}

// decodeProof deserializes an 81-byte proof into (Gamma, c, s).
func decodeProof(pi [81]byte) (*secp256k1.PublicKey, *secp256k1.ModNScalar, *secp256k1.ModNScalar, error) {
	Gamma, err := secp256k1.ParsePubKey(pi[:PtLen])
	if err != nil {
		return nil, nil, nil, ErrInvalidProof
	}

	var c secp256k1.ModNScalar
	c.SetByteSlice(pi[PtLen : PtLen+CLen])

	var s secp256k1.ModNScalar
	// SetByteSlice returns true if the value was reduced mod N, meaning the
	// original was >= N and therefore not a valid scalar in the proof.
	if s.SetByteSlice(pi[PtLen+CLen:]) {
		return nil, nil, nil, ErrInvalidProof
	}

	return Gamma, &c, &s, nil
}

// --- Helper functions ---

// jacobianToPublicKey converts a Jacobian point to an affine PublicKey.
func jacobianToPublicKey(j *secp256k1.JacobianPoint) *secp256k1.PublicKey {
	var p secp256k1.JacobianPoint
	p.Set(j)
	p.ToAffine()
	return secp256k1.NewPublicKey(&p.X, &p.Y)
}

// zeroBytes32 overwrites a 32-byte array with zeros.
func zeroBytes32(b *[32]byte) {
	for i := range b {
		b[i] = 0
	}
}
