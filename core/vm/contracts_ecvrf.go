// Package vm contains the ECVRF verify precompiled contract for the OP Stack.
//
// This file is designed to be integrated into op-geth's core/vm package.
// The precompile is registered at address 0x0101 (following Fjord's P256 at 0x0100).
package vm

import (
	"bytes"
	"errors"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

const (
	// EcvrfVerifyGas is the gas cost for the ECVRF verify precompile.
	EcvrfVerifyGas uint64 = 3000

	// ecvrfVerifyInputLen is the expected input length:
	// 33 (compressed PK) + 32 (alpha/seed) + 32 (beta) + 81 (pi) = 178 bytes
	ecvrfVerifyInputLen = 33 + 32 + 32 + 81 // 178
)

var (
	ecvrfValid   = []byte{0x01}
	ecvrfInvalid = []byte{0x00}

	errEcvrfInvalidInputLen = errors.New("ecvrf: invalid input length")
)

// EcvrfVerify implements the ECVRF verify precompiled contract.
//
// Address: 0x0101 (OP Stack extended precompile range)
//
// Input format:
//
//	[33 bytes: compressed SEC1 public key]
//	[32 bytes: alpha/seed]
//	[32 bytes: expected beta (VRF output)]
//	[81 bytes: pi (VRF proof)]
//	Total: 178 bytes
//
// Output format:
//
//	[1 byte: 0x01 if valid, 0x00 if invalid]
type EcvrfVerify struct{}

// RequiredGas returns the gas required to execute the precompile.
func (c *EcvrfVerify) RequiredGas(input []byte) uint64 {
	return EcvrfVerifyGas
}

// Run executes the ECVRF verify precompile.
func (c *EcvrfVerify) Run(input []byte) ([]byte, error) {
	if len(input) != ecvrfVerifyInputLen {
		return nil, errEcvrfInvalidInputLen
	}

	// Parse input fields
	pkBytes := input[0:33]
	alpha := input[33:65]
	expectedBeta := input[65:97]
	piBytes := input[97:178]

	// Parse public key
	pk, err := secp256k1.ParsePubKey(pkBytes)
	if err != nil {
		return ecvrfInvalid, nil
	}

	// Parse proof
	var pi [ecvrf.ProofLen]byte
	copy(pi[:], piBytes)

	// Verify the proof
	valid, beta, err := ecvrf.Verify(pk, alpha, pi)
	if err != nil || !valid {
		return ecvrfInvalid, nil
	}

	// Check that the computed beta matches the expected beta
	if !bytes.Equal(beta[:], expectedBeta) {
		return ecvrfInvalid, nil
	}

	return ecvrfValid, nil
}

