package derive

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"math/big"
	"strings"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"

	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

// ComputeVRFSeed computes the VRF seed from the block number and nonce.
// seed = sha256(blockNumber || nonce), each encoded as a 32-byte big-endian
// uint256 to match the on-chain abi.encode(uint256,uint256) layout.
// Each (blockNumber, nonce) pair produces a unique seed, allowing multiple
// VRF commitments per block. Unpredictability is guaranteed by the
// TEE-protected secret key — the sequencer cannot compute VRF outputs without
// the enclave, so a predictable seed does not weaken the scheme.
func ComputeVRFSeed(blockNumber uint64, nonce uint64) [32]byte {
	var buf [32]byte
	h := sha256.New()
	binary.BigEndian.PutUint64(buf[24:], blockNumber)
	h.Write(buf[:])
	buf = [32]byte{}
	binary.BigEndian.PutUint64(buf[24:], nonce)
	h.Write(buf[:])
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
	// Close releases resources: local provers zero sk in memory, TEE provers
	// tear down the gRPC connection. Safe to call once at node shutdown.
	Close() error
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

// Close zeroes the secret key scalar in-place.
func (l *LocalVRFProver) Close() error {
	if l.sk != nil {
		l.sk.Key.Zero()
		l.sk = nil
	}
	return nil
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

	// commitRandomnessArgs describes the ABI-encoded argument layout of
	// commitRandomness(uint256,bytes32,bytes32,bytes) so the decoder validates
	// types instead of chasing hardcoded byte offsets.
	commitRandomnessArgs = abi.Arguments{
		{Type: abiType("uint256")},
		{Type: abiType("bytes32")},
		{Type: abiType("bytes32")},
		{Type: abiType("bytes")},
	}
)

func abiType(s string) abi.Type {
	t, err := abi.NewType(s, "", nil)
	if err != nil {
		panic(fmt.Sprintf("invalid abi type %q: %v", s, err))
	}
	return t
}

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

// decodeCommitRandomness decodes the ABI-encoded commitRandomness calldata
// using the declared argument types; any deviation from the expected layout
// (wrong selector length, truncated data, wrong pi length) returns nil.
func decodeCommitRandomness(data []byte) *vrfCommitment {
	if len(data) < 4 {
		return nil
	}
	values, err := commitRandomnessArgs.Unpack(data[4:])
	if err != nil {
		return nil
	}

	nonce, ok := values[0].(*big.Int)
	if !ok {
		return nil
	}
	seed, ok := values[1].([32]byte)
	if !ok {
		return nil
	}
	beta, ok := values[2].([32]byte)
	if !ok {
		return nil
	}
	pi, ok := values[3].([]byte)
	if !ok || len(pi) != 81 {
		return nil
	}

	c := &vrfCommitment{
		nonce: nonce.Uint64(),
		seed:  seed,
		beta:  beta,
	}
	copy(c.pi[:], pi)
	return c
}
