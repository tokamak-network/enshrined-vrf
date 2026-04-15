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
)

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
	// Domain separator for VRF deposits (distinct from L1Info deposits)
	domain := common.Hash{0x02} // 0x02 = VRF deposit domain
	data := crypto.Keccak256(
		domain.Bytes(),
		common.BigToHash(new(big.Int).SetUint64(blockNumber)).Bytes(),
		common.BigToHash(new(big.Int).SetUint64(nonce)).Bytes(),
	)
	return common.BytesToHash(data)
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
