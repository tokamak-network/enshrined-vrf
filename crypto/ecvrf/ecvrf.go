package ecvrf

import (
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"math/big"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
)

var (
	// curve order as big.Int for modular arithmetic in nonce/challenge steps
	curveN = secp256k1.S256().N

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
	k := nonceGenerationRFC6979(sk, hBytes)

	// Step 5: U = k * G
	var kScalar secp256k1.ModNScalar
	kScalar.SetByteSlice(i2osp(k, QLen))
	var U secp256k1.JacobianPoint
	secp256k1.ScalarBaseMultNonConst(&kScalar, &U)

	// Step 6: V = k * H
	var V secp256k1.JacobianPoint
	secp256k1.ScalarMultNonConst(&kScalar, &HJac, &V)

	// Step 7: c = ECVRF_challenge_generation(Y, H, Gamma, U, V)
	c := challengeGeneration(pk, H, GammaAff, &U, &V)

	// Step 8: s = (k - c * sk) mod q
	skBytes := sk.Key.Bytes()
	skInt := new(big.Int).SetBytes(skBytes[:])
	s := new(big.Int).Mul(c, skInt)
	s.Sub(k, s)
	s.Mod(s, curveN)

	// Step 9: encode proof
	pi = encodeProof(GammaAff, c, s)

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

	// Convert scalars to ModNScalar
	var cScalar, sScalar secp256k1.ModNScalar
	cScalar.SetByteSlice(i2osp(c, QLen))
	sScalar.SetByteSlice(i2osp(s, QLen))

	// Step 3: U = s*G + c*Y
	var sG, cY, U secp256k1.JacobianPoint
	secp256k1.ScalarBaseMultNonConst(&sScalar, &sG)
	var pkJac secp256k1.JacobianPoint
	pk.AsJacobian(&pkJac)
	secp256k1.ScalarMultNonConst(&cScalar, &pkJac, &cY)
	secp256k1.AddNonConst(&sG, &cY, &U)

	// Step 4: V = s*H + c*Gamma
	var sH, cGamma, V secp256k1.JacobianPoint
	var HJac secp256k1.JacobianPoint
	H.AsJacobian(&HJac)
	secp256k1.ScalarMultNonConst(&sScalar, &HJac, &sH)
	var GammaJac secp256k1.JacobianPoint
	Gamma.AsJacobian(&GammaJac)
	secp256k1.ScalarMultNonConst(&cScalar, &GammaJac, &cGamma)
	secp256k1.AddNonConst(&sH, &cGamma, &V)

	// Step 5: c' = ECVRF_challenge_generation(Y, H, Gamma, U, V)
	cPrime := challengeGeneration(pk, H, Gamma, &U, &V)

	// Step 6: If c == c', output "VALID" and beta
	if c.Cmp(cPrime) != 0 {
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
		candidate := make([]byte, PtLen)
		candidate[0] = 0x02
		copy(candidate[1:], hash)

		point, err := secp256k1.ParsePubKey(candidate)
		if err != nil {
			continue
		}

		return point, nil
	}

	return nil, errors.New("ecvrf: encode_to_curve failed after 255 attempts")
}

// challengeGeneration implements ECVRF_challenge_generation per RFC 9381 Section 5.4.3.
func challengeGeneration(Y, H, Gamma *secp256k1.PublicKey, U, V *secp256k1.JacobianPoint) *big.Int {
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

	// Truncate to CLen bytes
	return new(big.Int).SetBytes(hash[:CLen])
}

// nonceGenerationRFC6979 generates a deterministic nonce k per RFC 6979.
func nonceGenerationRFC6979(sk *secp256k1.PrivateKey, hBytes []byte) *big.Int {
	// x = secret key as bytes
	skBytes := sk.Key.Bytes()
	x := skBytes[:]

	// h1 = SHA256(hBytes)
	h1Hash := sha256.Sum256(hBytes)
	h1 := h1Hash[:]

	// Step (b): V = 0x01 repeated
	v := make([]byte, 32)
	for i := range v {
		v[i] = 0x01
	}

	// Step (c): K = 0x00 repeated
	kk := make([]byte, 32)

	// Step (d): K = HMAC_K(V || 0x00 || int2octets(x) || bits2octets(h1))
	kk = hmacSHA256(kk, v, []byte{0x00}, x, h1)

	// Step (e): V = HMAC_K(V)
	v = hmacSHA256(kk, v)

	// Step (f): K = HMAC_K(V || 0x01 || int2octets(x) || bits2octets(h1))
	kk = hmacSHA256(kk, v, []byte{0x01}, x, h1)

	// Step (g): V = HMAC_K(V)
	v = hmacSHA256(kk, v)

	// Step (h): Generate k
	for {
		v = hmacSHA256(kk, v)
		k := new(big.Int).SetBytes(v)
		if k.Sign() > 0 && k.Cmp(curveN) < 0 {
			return k
		}
		kk = hmacSHA256(kk, v, []byte{0x00})
		v = hmacSHA256(kk, v)
	}
}

// encodeProof serializes (Gamma, c, s) into an 81-byte proof.
func encodeProof(Gamma *secp256k1.PublicKey, c, s *big.Int) [81]byte {
	var pi [81]byte
	copy(pi[:PtLen], Gamma.SerializeCompressed())
	copy(pi[PtLen:PtLen+CLen], i2osp(c, CLen))
	copy(pi[PtLen+CLen:], i2osp(s, QLen))
	return pi
}

// decodeProof deserializes an 81-byte proof into (Gamma, c, s).
func decodeProof(pi [81]byte) (*secp256k1.PublicKey, *big.Int, *big.Int, error) {
	Gamma, err := secp256k1.ParsePubKey(pi[:PtLen])
	if err != nil {
		return nil, nil, nil, ErrInvalidProof
	}

	c := new(big.Int).SetBytes(pi[PtLen : PtLen+CLen])
	s := new(big.Int).SetBytes(pi[PtLen+CLen:])

	if s.Cmp(curveN) >= 0 {
		return nil, nil, nil, ErrInvalidProof
	}

	return Gamma, c, s, nil
}

// --- Helper functions ---

// i2osp converts a non-negative integer to a big-endian byte string of the given length.
func i2osp(x *big.Int, length int) []byte {
	b := x.Bytes()
	if len(b) >= length {
		return b[len(b)-length:]
	}
	result := make([]byte, length)
	copy(result[length-len(b):], b)
	return result
}

// hmacSHA256 computes HMAC-SHA256 with the given key and concatenated data.
func hmacSHA256(key []byte, data ...[]byte) []byte {
	mac := hmac.New(sha256.New, key)
	for _, d := range data {
		mac.Write(d)
	}
	return mac.Sum(nil)
}

// jacobianToPublicKey converts a Jacobian point to an affine PublicKey.
func jacobianToPublicKey(j *secp256k1.JacobianPoint) *secp256k1.PublicKey {
	// Make a copy to avoid mutating the input
	var p secp256k1.JacobianPoint
	p.Set(j)
	p.ToAffine()
	return secp256k1.NewPublicKey(&p.X, &p.Y)
}
