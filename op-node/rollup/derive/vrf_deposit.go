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

	// commitRandomness(uint256,bytes32,bytes)
	vrfCommitSelector = crypto.Keccak256([]byte("commitRandomness(uint256,bytes32,bytes)"))[:4]
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
// a VRF result (beta, pi) to the PredeployedVRF contract.
// This is called by the sequencer during block building.
func VRFCommitRandomnessDeposit(nonce uint64, beta [32]byte, pi [81]byte, sourceHash common.Hash) (*types.DepositTx, error) {
	// ABI encode: commitRandomness(uint256,bytes32,bytes)
	nonceBytes := common.BigToHash(new(big.Int).SetUint64(nonce))

	// Dynamic encoding for pi (bytes)
	// offset to dynamic data for pi parameter
	offset := make([]byte, 32)
	offset[31] = 0x60 // 3 * 32 = 96

	piLength := make([]byte, 32)
	piLength[31] = 81

	// Pad pi to multiple of 32 bytes (81 -> 96)
	piPadded := make([]byte, 96)
	copy(piPadded, pi[:])

	data := make([]byte, 0, 4+32+32+32+32+96)
	data = append(data, vrfCommitSelector...)
	data = append(data, nonceBytes.Bytes()...)
	data = append(data, beta[:]...)
	data = append(data, offset...)
	data = append(data, piLength...)
	data = append(data, piPadded...)

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

// ComputeVRFSeed computes the VRF seed from prevrandao and block number.
// seed = sha256(prevrandao || blockNumber)
// The nonce is excluded from the seed to avoid cross-component state synchronization.
// Block-level uniqueness is guaranteed by prevrandao + blockNumber.
func ComputeVRFSeed(prevrandao common.Hash, blockNumber uint64) [32]byte {
	h := sha256.New()
	h.Write(prevrandao.Bytes())
	blockNumBytes := common.BigToHash(new(big.Int).SetUint64(blockNumber))
	h.Write(blockNumBytes.Bytes())
	var seed [32]byte
	copy(seed[:], h.Sum(nil))
	return seed
}

// ComputeVRFProof computes the VRF proof using the sequencer's private key.
// This is called by op-node during block building. The private key never leaves op-node.
func ComputeVRFProof(privateKey *secp256k1.PrivateKey, prevrandao common.Hash, blockNumber uint64) (beta [32]byte, pi [81]byte, err error) {
	seed := ComputeVRFSeed(prevrandao, blockNumber)
	return ecvrf.Prove(privateKey, seed[:])
}

// LoadVRFKey parses a hex-encoded secp256k1 private key for VRF proving.
func LoadVRFKey(hexKey string) (*secp256k1.PrivateKey, error) {
	hexKey = strings.TrimPrefix(hexKey, "0x")
	if len(hexKey) != 64 {
		return nil, fmt.Errorf("VRF key must be 32 bytes (64 hex characters), got %d", len(hexKey))
	}
	privECDSA, err := crypto.HexToECDSA(hexKey)
	if err != nil {
		return nil, fmt.Errorf("failed to parse VRF private key: %w", err)
	}
	return secp256k1.PrivKeyFromBytes(privECDSA.D.Bytes()), nil
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
	if len(attrs.VRFProofBeta) == 32 && len(attrs.VRFProofPi) == 81 && attrs.VRFNonce != nil {
		var beta [32]byte
		var pi [81]byte
		copy(beta[:], attrs.VRFProofBeta)
		copy(pi[:], attrs.VRFProofPi)

		sourceHash := computeVRFSourceHash(uint64(attrs.Timestamp), *attrs.VRFNonce)
		commitDeposit, err := VRFCommitRandomnessDeposit(*attrs.VRFNonce, beta, pi, sourceHash)
		if err != nil {
			return nil, err
		}
		deposits = append(deposits, commitDeposit)
	}

	return deposits, nil
}
