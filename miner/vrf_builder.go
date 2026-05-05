package miner

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/log"
)

var (
	// PredeployedVRF contract address on L2
	enshrainedVRFAddr = common.HexToAddress("0x42000000000000000000000000000000000000f0")

	// L1InfoDepositerAddress is the depositor account for system transactions
	vrfDepositorAddr = common.HexToAddress("0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001")

	// Function selectors
	// commitRandomness(uint256,bytes32,bytes32,bytes)
	commitRandomnessSelector = crypto.Keccak256([]byte("commitRandomness(uint256,bytes32,bytes32,bytes)"))[:4]
	// setSequencerPublicKey(bytes)
	setSequencerPublicKeySelector = crypto.Keccak256([]byte("setSequencerPublicKey(bytes)"))[:4]
)

// buildVRFPublicKeyDepositTx creates a system deposit transaction that syncs
// the sequencer VRF public key from L1 SystemConfig into the L2 predeploy.
func (miner *Miner) buildVRFPublicKeyDepositTx(env *environment, pk []byte) (*types.Transaction, error) {
	if !miner.chainConfig.IsEnshrainedVRF(env.header.Time) {
		return nil, nil // fork not active
	}
	if len(pk) == 0 {
		return nil, nil // key not configured on L1 SystemConfig yet
	}
	if len(pk) != 33 {
		return nil, fmt.Errorf("invalid VRF public key length: %d", len(pk))
	}

	log.Info("VRF public key deposit tx",
		"blockNumber", env.header.Number,
		"publicKey", common.Bytes2Hex(pk[:4]),
	)

	depositTx := types.NewTx(&types.DepositTx{
		SourceHash:          computeVRFPublicKeySourceHash(env.header.Number.Uint64()),
		From:                vrfDepositorAddr,
		To:                  &enshrainedVRFAddr,
		Mint:                big.NewInt(0),
		Value:               big.NewInt(0),
		Gas:                 300_000,
		IsSystemTransaction: false, // Must be false post-Regolith
		Data:                encodeSetSequencerPublicKey(pk),
	})

	return depositTx, nil
}

// buildVRFDepositTx creates a system deposit transaction that commits VRF
// randomness to the PredeployedVRF contract. The VRF proof is pre-computed
// by op-node and passed via PayloadAttributes. op-geth never holds the
// VRF private key.
func (miner *Miner) buildVRFDepositTx(env *environment, genParam *generateParams) (*types.Transaction, error) {
	if !miner.chainConfig.IsEnshrainedVRF(env.header.Time) {
		return nil, nil // fork not active
	}

	// VRF proof must be provided by op-node via PayloadAttributes
	if len(genParam.vrfSeed) != 32 || len(genParam.vrfProofBeta) != 32 || len(genParam.vrfProofPi) != 81 || genParam.vrfNonce == nil {
		return nil, fmt.Errorf("VRF proof not provided in PayloadAttributes (seed=%d, beta=%d, pi=%d bytes)",
			len(genParam.vrfSeed), len(genParam.vrfProofBeta), len(genParam.vrfProofPi))
	}

	var seed [32]byte
	var beta [32]byte
	var pi [81]byte
	copy(seed[:], genParam.vrfSeed)
	copy(beta[:], genParam.vrfProofBeta)
	copy(pi[:], genParam.vrfProofPi)
	nonce := *genParam.vrfNonce

	log.Info("VRF deposit tx from op-node proof",
		"blockNumber", env.header.Number,
		"nonce", nonce,
		"beta", common.Bytes2Hex(beta[:8]),
	)

	// Encode deposit tx data: commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes pi)
	data := encodeCommitRandomness(new(big.Int).SetUint64(nonce), seed, beta, pi)

	// Create source hash for the deposit tx
	sourceHash := computeVRFSourceHash(env.header.Number.Uint64(), nonce)

	depositTx := types.NewTx(&types.DepositTx{
		SourceHash:          sourceHash,
		From:                vrfDepositorAddr,
		To:                  &enshrainedVRFAddr,
		Mint:                big.NewInt(0),
		Value:               big.NewInt(0),
		Gas:                 1_000_000,
		IsSystemTransaction: false, // Must be false post-Regolith
		Data:                data,
	})

	return depositTx, nil
}

// computeVRFSourceHash creates a unique source hash for VRF deposit txs.
func computeVRFSourceHash(blockNumber, nonce uint64) common.Hash {
	return computeVRFSystemSourceHash(0x02, blockNumber, nonce)
}

// computeVRFPublicKeySourceHash creates a unique source hash for VRF public
// key update deposit txs.
func computeVRFPublicKeySourceHash(blockNumber uint64) common.Hash {
	return computeVRFSystemSourceHash(0x03, blockNumber, 0)
}

func computeVRFSystemSourceHash(domainByte byte, blockNumber, value uint64) common.Hash {
	// Domain separator for VRF system deposits (distinct from L1Info deposits)
	domain := common.Hash{domainByte}
	data := crypto.Keccak256(
		domain.Bytes(),
		common.BigToHash(new(big.Int).SetUint64(blockNumber)).Bytes(),
		common.BigToHash(new(big.Int).SetUint64(value)).Bytes(),
	)
	return common.BytesToHash(data)
}

// encodeSetSequencerPublicKey ABI-encodes setSequencerPublicKey(bytes).
func encodeSetSequencerPublicKey(pk []byte) []byte {
	data := make([]byte, 0, 4+32+32+64)
	data = append(data, setSequencerPublicKeySelector...)

	// bytes pk (dynamic type), offset to dynamic data = 32
	offset := common.BigToHash(big.NewInt(32))
	data = append(data, offset.Bytes()...)

	pkLen := common.BigToHash(new(big.Int).SetUint64(uint64(len(pk))))
	data = append(data, pkLen.Bytes()...)

	// 33-byte compressed SEC1 key padded to 64 bytes.
	pkPadded := make([]byte, 64)
	copy(pkPadded, pk)
	data = append(data, pkPadded...)

	return data
}

// encodeCommitRandomness ABI-encodes commitRandomness(uint256,bytes32,bytes32,bytes)
func encodeCommitRandomness(nonce *big.Int, seed [32]byte, beta [32]byte, pi [81]byte) []byte {
	// Function selector
	data := make([]byte, 0, 4+32+32+32+32+32+96)
	data = append(data, commitRandomnessSelector...)

	// uint256 nonce
	nonceBytes := common.BigToHash(nonce)
	data = append(data, nonceBytes.Bytes()...)

	// bytes32 seed
	data = append(data, seed[:]...)

	// bytes32 beta
	data = append(data, beta[:]...)

	// bytes pi (dynamic type)
	// offset to dynamic data = 4 * 32 = 128
	offset := common.BigToHash(big.NewInt(128))
	data = append(data, offset.Bytes()...)

	// length of pi = 81
	piLen := common.BigToHash(big.NewInt(81))
	data = append(data, piLen.Bytes()...)

	// pi data padded to 96 bytes (next multiple of 32 after 81)
	piPadded := make([]byte, 96)
	copy(piPadded, pi[:])
	data = append(data, piPadded...)

	return data
}
