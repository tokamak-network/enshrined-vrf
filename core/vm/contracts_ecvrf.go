package vm

import (
	"bytes"

	"github.com/ethereum/go-ethereum/crypto/ecvrf"
	"github.com/ethereum/go-ethereum/log"
	"github.com/ethereum/go-ethereum/params"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
)

// ecvrfVerify implements the ECVRF verify precompiled contract.
//
// Address: 0x0101 (OP Stack extended precompile range, after P256 at 0x0100)
//
// Input:  [33 bytes PK][32 bytes alpha][32 bytes beta][81 bytes pi] = 178 bytes
// Output: [1 byte: 0x01 valid / 0x00 invalid]
type ecvrfVerify struct{}

func (c *ecvrfVerify) Name() string {
	return "ecvrfVerify"
}

func (c *ecvrfVerify) RequiredGas(input []byte) uint64 {
	return params.EcvrfVerifyGas
}

func (c *ecvrfVerify) Run(input []byte) ([]byte, error) {
	const inputLen = 33 + 32 + 32 + 81 // 178
	if len(input) != inputLen {
		return nil, nil
	}

	pk, err := secp256k1.ParsePubKey(input[0:33])
	if err != nil {
		return []byte{0x00}, nil
	}

	alpha := input[33:65]
	expectedBeta := input[65:97]
	var pi [ecvrf.ProofLen]byte
	copy(pi[:], input[97:178])

	valid, beta, err := ecvrf.Verify(pk, alpha, pi)
	if err != nil {
		// Surface unexpected verify failures (e.g. malformed scalar in pi).
		// The normal "invalid proof" path returns valid=false with nil err
		// and stays silent.
		log.Debug("ECVRF verify error", "err", err)
		return []byte{0x00}, nil
	}
	if !valid {
		return []byte{0x00}, nil
	}

	if !bytes.Equal(beta[:], expectedBeta) {
		return []byte{0x00}, nil
	}

	return []byte{0x01}, nil
}
