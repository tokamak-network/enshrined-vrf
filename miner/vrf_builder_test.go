package miner

import (
	"bytes"
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/params"
)

func TestEncodeSetSequencerPublicKey(t *testing.T) {
	pk := append([]byte{0x02}, bytes.Repeat([]byte{0x42}, 32)...)
	data := encodeSetSequencerPublicKey(pk)

	if !bytes.Equal(data[:4], setSequencerPublicKeySelector) {
		t.Fatalf("unexpected selector: got %x want %x", data[:4], setSequencerPublicKeySelector)
	}

	bytesTy, err := abi.NewType("bytes", "", nil)
	if err != nil {
		t.Fatalf("new abi type: %v", err)
	}
	args := abi.Arguments{{Type: bytesTy}}
	values, err := args.Unpack(data[4:])
	if err != nil {
		t.Fatalf("unpack calldata: %v", err)
	}
	got, ok := values[0].([]byte)
	if !ok {
		t.Fatalf("decoded public key has type %T", values[0])
	}
	if !bytes.Equal(got, pk) {
		t.Fatalf("decoded public key mismatch: got %x want %x", got, pk)
	}
}

func TestVRFSystemSourceHashDomainsDoNotCollide(t *testing.T) {
	blockNumber := uint64(42)
	nonce := uint64(7)

	randomnessHash := computeVRFSourceHash(blockNumber, nonce)
	publicKeyHash := computeVRFPublicKeySourceHash(blockNumber)
	if randomnessHash == publicKeyHash {
		t.Fatalf("VRF randomness and public-key source hashes must use distinct domains")
	}
}

func TestBuildVRFPublicKeyDepositTx(t *testing.T) {
	activation := uint64(0)
	blockNumber := uint64(42)
	pk := append([]byte{0x02}, bytes.Repeat([]byte{0x42}, 32)...)

	miner := &Miner{
		chainConfig: &params.ChainConfig{
			EnshrainedVRFTime: &activation,
		},
	}
	env := &environment{
		header: &types.Header{
			Number: new(big.Int).SetUint64(blockNumber),
			Time:   activation,
		},
	}

	tx, err := miner.buildVRFPublicKeyDepositTx(env, pk)
	if err != nil {
		t.Fatalf("build public-key deposit tx: %v", err)
	}
	if tx == nil {
		t.Fatalf("expected public-key deposit tx")
	}
	if !tx.IsDepositTx() {
		t.Fatalf("expected deposit tx, got type %d", tx.Type())
	}
	if tx.IsSystemTx() {
		t.Fatalf("public-key deposit tx must be metered post-Regolith")
	}
	if got, want := tx.SourceHash(), computeVRFPublicKeySourceHash(blockNumber); got != want {
		t.Fatalf("source hash mismatch: got %s want %s", got, want)
	}
	vrfAddr := common.HexToAddress("0x42000000000000000000000000000000000000f0")
	if got := tx.To(); got == nil || *got != vrfAddr {
		t.Fatalf("unexpected tx recipient: %v", got)
	}
	if got := tx.Gas(); got != 300_000 {
		t.Fatalf("unexpected gas: got %d", got)
	}
	if !bytes.Equal(tx.Data(), encodeSetSequencerPublicKey(pk)) {
		t.Fatalf("unexpected calldata")
	}
}
