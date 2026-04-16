package derive

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"math/big"
	"strings"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
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

var (
	// EnshrainedVRF predeploy address on L2
	enshrainedVRFAddr = common.HexToAddress("0x42000000000000000000000000000000000000f0")

	// commitRandomness(uint256,bytes32,bytes32,bytes) selector
	commitRandomnessSelector = crypto.Keccak256([]byte("commitRandomness(uint256,bytes32,bytes32,bytes)"))[:4]

	// L1Info depositor address (also used for VRF deposits)
	vrfDepositorAddr = common.HexToAddress("0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001")
)

// vrfCommitment holds VRF data extracted from a deposit transaction.
type vrfCommitment struct {
	nonce uint64
	seed  [32]byte
	beta  [32]byte
	pi    [81]byte
}

// extractVRFFromDeposits scans deposit transactions for a VRF commitment.
// Returns nil if no VRF deposit is found.
func extractVRFFromDeposits(txs types.Transactions) *vrfCommitment {
	for _, tx := range txs {
		if tx.Type() != types.DepositTxType {
			continue
		}
		if tx.To() == nil || *tx.To() != enshrainedVRFAddr {
			continue
		}
		data := tx.Data()
		if len(data) < 4 || !bytes.Equal(data[:4], commitRandomnessSelector) {
			continue
		}
		return decodeCommitRandomness(data)
	}
	return nil
}

// decodeCommitRandomness decodes the ABI-encoded commitRandomness calldata.
// Layout: selector(4) + nonce(32) + seed(32) + beta(32) + offset(32) + piLen(32) + piData(96)
func decodeCommitRandomness(data []byte) *vrfCommitment {
	const expectedMinLen = 4 + 32 + 32 + 32 + 32 + 32 + 81 // 245
	if len(data) < expectedMinLen {
		return nil
	}

	c := &vrfCommitment{}

	// nonce: bytes 4..36
	nonceBig := new(big.Int).SetBytes(data[4:36])
	c.nonce = nonceBig.Uint64()

	// seed: bytes 36..68
	copy(c.seed[:], data[36:68])

	// beta: bytes 68..100
	copy(c.beta[:], data[68:100])

	// offset to dynamic data: bytes 100..132 (should be 128 = 0x80)
	// pi length: bytes 132..164 (should be 81)
	piLenBig := new(big.Int).SetBytes(data[132:164])
	piLen := piLenBig.Uint64()
	if piLen != 81 || len(data) < 164+81 {
		return nil
	}

	// pi data: bytes 164..245
	copy(c.pi[:], data[164:245])

	return c
}
