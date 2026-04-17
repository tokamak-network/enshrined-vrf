package derive

import (
	"bytes"
	"math/big"
	"testing"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/stretchr/testify/require"

	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

// buildVRFDepositTx constructs a VRF deposit transaction matching the format
// produced by op-geth/miner/vrf_builder.go. Used for testing only.
func buildVRFDepositTx(nonce uint64, seed [32]byte, beta [32]byte, pi [81]byte) *types.Transaction {
	data := encodeCommitRandomnessCalldata(new(big.Int).SetUint64(nonce), seed, beta, pi)

	to := enshrainedVRFAddr
	return types.NewTx(&types.DepositTx{
		SourceHash:          common.Hash{0x02},
		From:                vrfDepositorAddr,
		To:                  &to,
		Mint:                big.NewInt(0),
		Value:               big.NewInt(0),
		Gas:                 1_000_000,
		IsSystemTransaction: false,
		Data:                data,
	})
}

// encodeCommitRandomnessCalldata ABI-encodes commitRandomness(uint256,bytes32,bytes32,bytes).
func encodeCommitRandomnessCalldata(nonce *big.Int, seed [32]byte, beta [32]byte, pi [81]byte) []byte {
	selector := crypto.Keccak256([]byte("commitRandomness(uint256,bytes32,bytes32,bytes)"))[:4]
	data := make([]byte, 0, 4+32+32+32+32+32+96)
	data = append(data, selector...)
	data = append(data, common.BigToHash(nonce).Bytes()...)
	data = append(data, seed[:]...)
	data = append(data, beta[:]...)
	data = append(data, common.BigToHash(big.NewInt(128)).Bytes()...) // offset
	data = append(data, common.BigToHash(big.NewInt(81)).Bytes()...)  // pi length
	piPadded := make([]byte, 96)
	copy(piPadded, pi[:])
	data = append(data, piPadded...)
	return data
}

func TestExtractVRFFromDeposits(t *testing.T) {
	sk, err := secp256k1.GeneratePrivateKey()
	require.NoError(t, err)

	blockNumber := uint64(42)
	nonce := uint64(0)

	// Generate a real VRF proof
	seed := ComputeVRFSeed(blockNumber, nonce)
	beta, pi, err := ecvrf.Prove(sk, seed[:])
	require.NoError(t, err)

	// Build deposit tx as op-geth would
	vrfTx := buildVRFDepositTx(nonce, seed, beta, pi)

	// Also add a regular deposit (L1 info) that should be ignored
	l1InfoTo := common.HexToAddress("0x4200000000000000000000000000000000000015")
	l1InfoTx := types.NewTx(&types.DepositTx{
		SourceHash: common.Hash{0x01},
		From:       vrfDepositorAddr,
		To:         &l1InfoTo,
		Data:       []byte{0xde, 0xad},
	})

	txs := types.Transactions{l1InfoTx, vrfTx}

	t.Run("extracts VRF data correctly", func(t *testing.T) {
		result := extractVRFFromDeposits(txs)
		require.NotNil(t, result, "should find VRF deposit")
		require.Equal(t, nonce, result.nonce)
		require.Equal(t, seed, result.seed)
		require.Equal(t, beta, result.beta)
		require.Equal(t, pi, result.pi)
	})

	t.Run("returns nil when no VRF deposit", func(t *testing.T) {
		result := extractVRFFromDeposits(types.Transactions{l1InfoTx})
		require.Nil(t, result)
	})

	t.Run("returns nil for empty transactions", func(t *testing.T) {
		result := extractVRFFromDeposits(types.Transactions{})
		require.Nil(t, result)
	})
}

// TestVRFBatchRoundTrip verifies that VRF data survives the full batch pipeline:
// block → SingularBatch (encode) → SingularBatch (decode) → same VRF data.
// This is the core property that makes fault proofs work: the verifier
// reconstructs the same VRF deposit tx from batch data.
func TestVRFBatchRoundTrip(t *testing.T) {
	sk, err := secp256k1.GeneratePrivateKey()
	require.NoError(t, err)

	blockNumber := uint64(100)
	nonce := uint64(0)

	seed := ComputeVRFSeed(blockNumber, nonce)
	beta, pi, err := ecvrf.Prove(sk, seed[:])
	require.NoError(t, err)

	// Create a SingularBatch with VRF data (as the batcher would)
	original := &SingularBatch{
		ParentHash:   common.HexToHash("0xaabb"),
		EpochNum:     42,
		EpochHash:    common.HexToHash("0xccdd"),
		Timestamp:    1000,
		Transactions: nil,
		VRFSeed:      seed[:],
		VRFProofBeta: beta[:],
		VRFProofPi:   pi[:],
		VRFNonce:     nonce,
		VRFEnabled:   true,
	}

	// RLP encode and decode
	var buf bytes.Buffer
	err = original.encode(&buf)
	require.NoError(t, err)

	decoded := &SingularBatch{}
	reader := bytes.NewReader(buf.Bytes())
	err = decoded.decode(reader)
	require.NoError(t, err)

	// Verify all fields match
	require.Equal(t, original.ParentHash, decoded.ParentHash)
	require.Equal(t, original.EpochNum, decoded.EpochNum)
	require.Equal(t, original.Timestamp, decoded.Timestamp)
	require.Equal(t, original.VRFSeed, decoded.VRFSeed)
	require.Equal(t, original.VRFProofBeta, decoded.VRFProofBeta)
	require.Equal(t, original.VRFProofPi, decoded.VRFProofPi)
	require.Equal(t, original.VRFNonce, decoded.VRFNonce)
	require.Equal(t, original.VRFEnabled, decoded.VRFEnabled)
}

// TestVRFBatchRoundTripBackwardCompatible verifies that batches without VRF data
// can still be decoded correctly (pre-EnshrainedVRF fork).
func TestVRFBatchRoundTripBackwardCompatible(t *testing.T) {
	original := &SingularBatch{
		ParentHash:   common.HexToHash("0xaabb"),
		EpochNum:     42,
		EpochHash:    common.HexToHash("0xccdd"),
		Timestamp:    1000,
		Transactions: nil,
		// No VRF fields set
	}

	var buf bytes.Buffer
	err := original.encode(&buf)
	require.NoError(t, err)

	decoded := &SingularBatch{}
	reader := bytes.NewReader(buf.Bytes())
	err = decoded.decode(reader)
	require.NoError(t, err)

	require.Equal(t, original.ParentHash, decoded.ParentHash)
	require.Equal(t, original.EpochNum, decoded.EpochNum)
	require.Equal(t, original.Timestamp, decoded.Timestamp)
	require.False(t, decoded.VRFEnabled, "VRFEnabled should be false for pre-fork batches")
	require.Nil(t, decoded.VRFSeed)
	require.Nil(t, decoded.VRFProofBeta)
	require.Nil(t, decoded.VRFProofPi)
}

// TestVRFDeterministicSeedComputation verifies that the seed computation is
// deterministic — the same (blockNumber, nonce) always produces the same seed.
// This property is essential for fault proof re-execution.
func TestVRFDeterministicSeedComputation(t *testing.T) {
	blockNum := uint64(42)
	nonce := uint64(7)

	seed1 := ComputeVRFSeed(blockNum, nonce)
	seed2 := ComputeVRFSeed(blockNum, nonce)
	require.Equal(t, seed1, seed2, "seed must be deterministic")

	// Different inputs produce different seeds
	seed3 := ComputeVRFSeed(blockNum+1, nonce)
	require.NotEqual(t, seed1, seed3, "different block numbers must produce different seeds")

	seed4 := ComputeVRFSeed(blockNum, nonce+1)
	require.NotEqual(t, seed1, seed4, "different nonces must produce different seeds")
}

// TestVRFSpanBatchElementConversion verifies that VRF data is preserved
// when converting between SingularBatch and SpanBatchElement.
func TestVRFSpanBatchElementConversion(t *testing.T) {
	seed := [32]byte{1, 2, 3}
	beta := [32]byte{4, 5, 6}
	pi := [81]byte{7, 8, 9}

	singular := &SingularBatch{
		EpochNum:     42,
		Timestamp:    1000,
		Transactions: nil,
		VRFSeed:      seed[:],
		VRFProofBeta: beta[:],
		VRFProofPi:   pi[:],
		VRFNonce:     5,
		VRFEnabled:   true,
	}

	element := singularBatchToElement(singular)

	require.Equal(t, singular.VRFSeed, element.VRFSeed)
	require.Equal(t, singular.VRFProofBeta, element.VRFProofBeta)
	require.Equal(t, singular.VRFProofPi, element.VRFProofPi)
	require.Equal(t, singular.VRFNonce, element.VRFNonce)
	require.Equal(t, singular.VRFEnabled, element.VRFEnabled)
}

// TestVRFSpanBatchBinaryRoundTrip verifies that VRF data survives the full
// SpanBatch binary encoding/decoding round trip:
// SpanBatch → RawSpanBatch → encode → decode → RawSpanBatch → SpanBatch
func TestVRFSpanBatchBinaryRoundTrip(t *testing.T) {
	sk, err := secp256k1.GeneratePrivateKey()
	require.NoError(t, err)

	blockTime := uint64(2)
	genesisTimestamp := uint64(100)
	chainID := big.NewInt(901)

	// Create 3 blocks with VRF data
	elements := make([]*SpanBatchElement, 3)
	for i := 0; i < 3; i++ {
		blockNum := uint64(i + 1)
		nonce := uint64(i)
		seed := ComputeVRFSeed(blockNum, nonce)
		beta, pi, err := ecvrf.Prove(sk, seed[:])
		require.NoError(t, err)

		elements[i] = &SpanBatchElement{
			EpochNum:     42,
			Timestamp:    genesisTimestamp + blockTime*uint64(i),
			Transactions: nil,
			VRFSeed:      seed[:],
			VRFProofBeta: beta[:],
			VRFProofPi:   pi[:],
			VRFNonce:     nonce,
			VRFEnabled:   true,
		}
	}

	spanBatch := &SpanBatch{
		ParentCheck:      [20]byte{0xaa},
		L1OriginCheck:    [20]byte{0xbb},
		GenesisTimestamp: genesisTimestamp,
		ChainID:          chainID,
		Batches:          elements,
		originBits:       big.NewInt(0),     // no origin changes
		blockTxCounts:    []uint64{0, 0, 0}, // no txs
		sbtxs: &spanBatchTxs{
			totalBlockTxCount:    0,
			contractCreationBits: big.NewInt(0),
			yParityBits:          big.NewInt(0),
			protectedBits:        big.NewInt(0),
		},
	}

	// SpanBatch → RawSpanBatch
	rawBatch, err := spanBatch.ToRawSpanBatch()
	require.NoError(t, err)
	require.True(t, rawBatch.vrfEnabled, "VRF should be enabled in raw batch")

	// RawSpanBatch → binary → RawSpanBatch
	var buf bytes.Buffer
	err = rawBatch.encode(&buf)
	require.NoError(t, err)

	decoded := &RawSpanBatch{}
	reader := bytes.NewReader(buf.Bytes())
	err = decoded.decode(reader)
	require.NoError(t, err)

	require.True(t, decoded.vrfEnabled)
	require.Equal(t, uint64(3), decoded.blockCount)

	// Verify VRF data matches
	for i := 0; i < 3; i++ {
		require.Equal(t, rawBatch.vrfNonces[i], decoded.vrfNonces[i], "nonce mismatch at block %d", i)
		require.Equal(t, rawBatch.vrfSeeds[i], decoded.vrfSeeds[i], "seed mismatch at block %d", i)
		require.Equal(t, rawBatch.vrfBetas[i], decoded.vrfBetas[i], "beta mismatch at block %d", i)
		require.Equal(t, rawBatch.vrfPis[i], decoded.vrfPis[i], "pi mismatch at block %d", i)
	}

	// RawSpanBatch → SpanBatch (derive)
	derived, err := decoded.ToSpanBatch(blockTime, genesisTimestamp, chainID)
	require.NoError(t, err)

	for i := 0; i < 3; i++ {
		require.True(t, derived.Batches[i].VRFEnabled, "VRF should be enabled in derived batch element %d", i)
		require.Equal(t, elements[i].VRFSeed, derived.Batches[i].VRFSeed, "seed mismatch at derived element %d", i)
		require.Equal(t, elements[i].VRFProofBeta, derived.Batches[i].VRFProofBeta, "beta mismatch at derived element %d", i)
		require.Equal(t, elements[i].VRFProofPi, derived.Batches[i].VRFProofPi, "pi mismatch at derived element %d", i)
		require.Equal(t, elements[i].VRFNonce, derived.Batches[i].VRFNonce, "nonce mismatch at derived element %d", i)
	}
}

// TestVRFSpanBatchBinaryBackwardCompatible verifies that span batches without
// VRF data decode correctly (pre-EnshrainedVRF fork).
func TestVRFSpanBatchBinaryBackwardCompatible(t *testing.T) {
	blockTime := uint64(2)
	genesisTimestamp := uint64(100)
	chainID := big.NewInt(901)

	spanBatch := &SpanBatch{
		ParentCheck:      [20]byte{0xaa},
		L1OriginCheck:    [20]byte{0xbb},
		GenesisTimestamp: genesisTimestamp,
		ChainID:          chainID,
		Batches: []*SpanBatchElement{
			{EpochNum: 42, Timestamp: genesisTimestamp, Transactions: nil},
		},
		originBits:    big.NewInt(0),
		blockTxCounts: []uint64{0},
		sbtxs: &spanBatchTxs{
			totalBlockTxCount:    0,
			contractCreationBits: big.NewInt(0),
			yParityBits:          big.NewInt(0),
			protectedBits:        big.NewInt(0),
		},
	}

	rawBatch, err := spanBatch.ToRawSpanBatch()
	require.NoError(t, err)
	require.False(t, rawBatch.vrfEnabled)

	var buf bytes.Buffer
	err = rawBatch.encode(&buf)
	require.NoError(t, err)

	decoded := &RawSpanBatch{}
	err = decoded.decode(bytes.NewReader(buf.Bytes()))
	require.NoError(t, err)

	require.False(t, decoded.vrfEnabled)

	derived, err := decoded.ToSpanBatch(blockTime, genesisTimestamp, chainID)
	require.NoError(t, err)
	require.False(t, derived.Batches[0].VRFEnabled)
}
