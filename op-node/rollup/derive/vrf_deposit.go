package derive

import (
	"crypto/sha256"
	"fmt"
	"math/big"
	"strings"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"

	"github.com/ethereum-optimism/optimism/op-node/rollup"
	"github.com/ethereum-optimism/optimism/op-service/eth"
	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

var (
	// PredeployedVRF contract address
	EnshrainedVRFAddress = common.HexToAddress("0x42000000000000000000000000000000000000f0")

	// Function selectors
	// setSequencerPublicKey(bytes)
	vrfSetPKSelector = crypto.Keccak256([]byte("setSequencerPublicKey(bytes)"))[:4]

	// commitRandomness(uint256,bytes32,bytes32,bytes)
	vrfCommitSelector = crypto.Keccak256([]byte("commitRandomness(uint256,bytes32,bytes32,bytes)"))[:4]
)

// VRFSetPublicKeyDeposit creates a system deposit transaction that updates
// the sequencer's VRF public key on the PredeployedVRF contract.
// This is called when the VRF public key changes via L1 SystemConfig.
func VRFSetPublicKeyDeposit(seqNumber uint64, publicKey []byte) (*types.DepositTx, error) {
	// ABI encode: setSequencerPublicKey(bytes)
	// Function selector (4 bytes) + offset (32 bytes) + length (32 bytes) + data (padded to 32)
	offset := make([]byte, 32)
	offset[31] = 0x20 // offset to dynamic data

	length := make([]byte, 32)
	length[31] = byte(len(publicKey))

	// Pad publicKey to 32 bytes
	padded := make([]byte, 32)
	copy(padded, publicKey)

	data := make([]byte, 0, 4+32+32+32)
	data = append(data, vrfSetPKSelector...)
	data = append(data, offset...)
	data = append(data, length...)
	data = append(data, padded...)

	source := L1InfoDepositSource{
		L1BlockHash: common.BytesToHash(publicKey), // use PK hash as source identifier
		SeqNumber:   seqNumber,
	}

	return &types.DepositTx{
		SourceHash:          source.SourceHash(),
		From:                L1InfoDepositerAddress,
		To:                  &EnshrainedVRFAddress,
		Mint:                big.NewInt(0),
		Value:               big.NewInt(0),
		Gas:                 RegolithSystemTxGas,
		IsSystemTransaction: true,
		Data:                data,
	}, nil
}

// VRFCommitRandomnessDeposit creates a system deposit transaction that commits
// a VRF result (seed, beta, pi) to the PredeployedVRF contract.
// This is called by the sequencer during block building.
func VRFCommitRandomnessDeposit(nonce uint64, seed [32]byte, beta [32]byte, pi [81]byte, sourceHash common.Hash) (*types.DepositTx, error) {
	// ABI encode: commitRandomness(uint256,bytes32,bytes32,bytes)
	nonceBytes := common.BigToHash(new(big.Int).SetUint64(nonce))

	// Dynamic encoding for pi (bytes)
	// offset to dynamic data for pi parameter = 4 * 32 = 128
	offset := make([]byte, 32)
	offset[31] = 0x80 // 128

	piLength := make([]byte, 32)
	piLength[31] = 81

	// Pad pi to multiple of 32 bytes (81 -> 96)
	piPadded := make([]byte, 96)
	copy(piPadded, pi[:])

	data := make([]byte, 0, 4+32+32+32+32+32+96)
	data = append(data, vrfCommitSelector...)
	data = append(data, nonceBytes.Bytes()...) // uint256 nonce
	data = append(data, seed[:]...)            // bytes32 seed
	data = append(data, beta[:]...)            // bytes32 beta
	data = append(data, offset...)             // offset to pi
	data = append(data, piLength...)           // pi length
	data = append(data, piPadded...)           // pi data

	return &types.DepositTx{
		SourceHash:          sourceHash,
		From:                L1InfoDepositerAddress,
		To:                  &EnshrainedVRFAddress,
		Mint:                big.NewInt(0),
		Value:               big.NewInt(0),
		Gas:                 RegolithSystemTxGas,
		IsSystemTransaction: true,
		Data:                data,
	}, nil
}

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

// computeVRFSourceHash creates a unique source hash for VRF deposit txs.
func computeVRFSourceHash(blockNumber, nonce uint64) common.Hash {
	domain := common.Hash{0x02} // 0x02 = VRF deposit domain
	data := crypto.Keccak256(
		domain.Bytes(),
		common.BigToHash(new(big.Int).SetUint64(blockNumber)).Bytes(),
		common.BigToHash(new(big.Int).SetUint64(nonce)).Bytes(),
	)
	return common.BytesToHash(data)
}

// ShouldIncludeVRFDeposits returns true if the EnshrainedVRF fork is active
// for the given timestamp.
func ShouldIncludeVRFDeposits(rollupCfg *rollup.Config, timestamp uint64) bool {
	return rollupCfg.IsEnshrainedVRF(timestamp)
}

// CreateVRFSystemDeposits creates the system deposit transactions for VRF
// based on the payload attributes. Returns nil if EnshrainedVRF is not active.
func CreateVRFSystemDeposits(rollupCfg *rollup.Config, attrs *eth.PayloadAttributes, seqNumber uint64) ([]*types.DepositTx, error) {
	timestamp := uint64(attrs.Timestamp)
	if !ShouldIncludeVRFDeposits(rollupCfg, timestamp) {
		return nil, nil
	}

	var deposits []*types.DepositTx

	// If VRF public key is present, create a deposit to set it
	if len(attrs.VRFPublicKey) == 33 {
		pkDeposit, err := VRFSetPublicKeyDeposit(seqNumber, attrs.VRFPublicKey)
		if err != nil {
			return nil, err
		}
		deposits = append(deposits, pkDeposit)
	}

	// If VRF proof is present (computed by op-node), create the commit deposit
	if len(attrs.VRFSeed) == 32 && len(attrs.VRFProofBeta) == 32 && len(attrs.VRFProofPi) == 81 && attrs.VRFNonce != nil {
		var seed [32]byte
		var beta [32]byte
		var pi [81]byte
		copy(seed[:], attrs.VRFSeed)
		copy(beta[:], attrs.VRFProofBeta)
		copy(pi[:], attrs.VRFProofPi)

		sourceHash := computeVRFSourceHash(uint64(attrs.Timestamp), *attrs.VRFNonce)
		commitDeposit, err := VRFCommitRandomnessDeposit(*attrs.VRFNonce, seed, beta, pi, sourceHash)
		if err != nil {
			return nil, err
		}
		deposits = append(deposits, commitDeposit)
	}

	return deposits, nil
}
