package derive

import (
	"crypto/sha256"
	"fmt"
	"math/big"
	"strings"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"

	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

// ComputeVRFSeed computes the VRF seed from the block number and nonce.
// seed = sha256(blockNumber || nonce)
// Each (blockNumber, nonce) pair produces a unique seed, allowing multiple
// VRF commitments per block. Unpredictability is guaranteed by the
// TEE-protected secret key — the sequencer cannot compute VRF outputs without
// the enclave, so a predictable seed does not weaken the scheme.
func ComputeVRFSeed(blockNumber uint64, nonce uint64) [32]byte {
	h := sha256.New()
	blockNumBytes := common.BigToHash(new(big.Int).SetUint64(blockNumber))
	h.Write(blockNumBytes.Bytes())
	nonceBytes := common.BigToHash(new(big.Int).SetUint64(nonce))
	h.Write(nonceBytes.Bytes())
	var seed [32]byte
	copy(seed[:], h.Sum(nil))
	return seed
}

// VRFProver abstracts VRF proof generation to ensure unpredictability.
// If the sequencer knows the secret key (sk), it can compute future VRF
// outputs before building the block, breaking unpredictability and enabling
// transaction ordering manipulation. By hiding sk behind this interface,
// the sequencer delegates proving to an isolated environment (e.g. TEE)
// where sk is never exposed — preserving both verifiability and unpredictability.
type VRFProver interface {
	// Prove generates a VRF proof for the given seed.
	Prove(seed []byte) (beta [32]byte, pi [81]byte, err error)
	// PublicKey returns the compressed 33-byte secp256k1 public key.
	PublicKey() []byte
}

// LocalVRFProver holds the secret key in Go memory.
// WARNING: This breaks unpredictability — the operator can read sk.
// Suitable for development and testing only.
type LocalVRFProver struct {
	sk *secp256k1.PrivateKey
	pk []byte // cached compressed public key
}

// NewLocalVRFProver creates a LocalVRFProver from a hex-encoded private key.
func NewLocalVRFProver(hexKey string) (*LocalVRFProver, error) {
	hexKey = strings.TrimPrefix(hexKey, "0x")
	if len(hexKey) != 64 {
		return nil, fmt.Errorf("VRF key must be 32 bytes (64 hex characters), got %d", len(hexKey))
	}
	privECDSA, err := crypto.HexToECDSA(hexKey)
	if err != nil {
		return nil, fmt.Errorf("failed to parse VRF private key: %w", err)
	}
	sk := secp256k1.PrivKeyFromBytes(privECDSA.D.Bytes())
	return &LocalVRFProver{
		sk: sk,
		pk: sk.PubKey().SerializeCompressed(),
	}, nil
}

func (l *LocalVRFProver) Prove(seed []byte) (beta [32]byte, pi [81]byte, err error) {
	return ecvrf.Prove(l.sk, seed)
}

func (l *LocalVRFProver) PublicKey() []byte {
	return l.pk
}

// ComputeVRFProof computes the VRF proof for a block and nonce using the given prover.
func ComputeVRFProof(prover VRFProver, blockNumber uint64, nonce uint64) (beta [32]byte, pi [81]byte, err error) {
	seed := ComputeVRFSeed(blockNumber, nonce)
	return prover.Prove(seed[:])
}
