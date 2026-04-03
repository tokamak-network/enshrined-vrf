package miner

import (
	"crypto/sha256"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/crypto/ecvrf"
	"github.com/ethereum/go-ethereum/log"
)

var (
	// PredeployedVRF contract address on L2
	enshrainedVRFAddr = common.HexToAddress("0x42000000000000000000000000000000000000f0")

	// L1InfoDepositerAddress is the depositor account for system transactions
	vrfDepositorAddr = common.HexToAddress("0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001")

	// Function selectors
	// commitRandomness(uint256,bytes32,bytes)
	commitRandomnessSelector = crypto.Keccak256([]byte("commitRandomness(uint256,bytes32,bytes)"))[:4]
)

// buildVRFDepositTx creates a system deposit transaction that commits VRF
// randomness to the PredeployedVRF contract. This is called during block
// building by the sequencer.
//
// The sequencer computes ecvrf.Prove(sk, seed) and encodes the result as
// a deposit tx calling PredeployedVRF.commitRandomness(nonce, beta, pi).
func (miner *Miner) buildVRFDepositTx(env *environment, genParam *generateParams) (*types.Transaction, error) {
	if miner.vrfConfig.PrivateKey == nil {
		return nil, fmt.Errorf("VRF private key not configured")
	}

	if !miner.chainConfig.IsEnshrainedVRF(env.header.Time) {
		return nil, nil // fork not active
	}

	// Read the current commit nonce from PredeployedVRF storage
	// Storage slot 1 = _commitNonce (after _sequencerPublicKey at slot 0)
	nonceSlot := common.BigToHash(big.NewInt(1))
	nonceBytes := env.state.GetState(enshrainedVRFAddr, nonceSlot)
	nonce := new(big.Int).SetBytes(nonceBytes.Bytes())

	// Compute seed = keccak256(prevrandao, block.number, nonce)
	seed := computeVRFSeed(env.header.MixDigest, env.header.Number.Uint64(), nonce.Uint64())

	// Compute VRF proof
	beta, pi, err := ecvrf.Prove(miner.vrfConfig.PrivateKey, seed[:])
	if err != nil {
		return nil, fmt.Errorf("VRF prove failed: %w", err)
	}

	log.Info("VRF randomness computed",
		"blockNumber", env.header.Number,
		"nonce", nonce,
		"beta", common.Bytes2Hex(beta[:8]),
	)

	// Encode deposit tx data: commitRandomness(uint256 nonce, bytes32 beta, bytes pi)
	data := encodeCommitRandomness(nonce, beta, pi)

	// Create source hash for the deposit tx
	sourceHash := computeVRFSourceHash(env.header.Number.Uint64(), nonce.Uint64())

	depositTx := types.NewTx(&types.DepositTx{
		SourceHash:          sourceHash,
		From:                vrfDepositorAddr,
		To:                  &enshrainedVRFAddr,
		Mint:                big.NewInt(0),
		Value:               big.NewInt(0),
		Gas:                 1_000_000, // RegolithSystemTxGas
		IsSystemTransaction: true,
		Data:                data,
	})

	return depositTx, nil
}

// computeVRFSeed computes seed = keccak256(abi.encodePacked(prevrandao, blockNumber, nonce))
func computeVRFSeed(prevrandao common.Hash, blockNumber, nonce uint64) [32]byte {
	h := sha256.New()
	h.Write(prevrandao.Bytes())
	blockNumBytes := common.BigToHash(new(big.Int).SetUint64(blockNumber))
	h.Write(blockNumBytes.Bytes())
	nonceBytes := common.BigToHash(new(big.Int).SetUint64(nonce))
	h.Write(nonceBytes.Bytes())
	var seed [32]byte
	copy(seed[:], h.Sum(nil))
	return seed
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

// encodeCommitRandomness ABI-encodes commitRandomness(uint256,bytes32,bytes)
func encodeCommitRandomness(nonce *big.Int, beta [32]byte, pi [81]byte) []byte {
	// Function selector
	data := make([]byte, 0, 4+32+32+32+32+96)
	data = append(data, commitRandomnessSelector...)

	// uint256 nonce
	nonceBytes := common.BigToHash(nonce)
	data = append(data, nonceBytes.Bytes()...)

	// bytes32 beta
	data = append(data, beta[:]...)

	// bytes pi (dynamic type)
	// offset to dynamic data = 3 * 32 = 96
	offset := common.BigToHash(big.NewInt(96))
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
