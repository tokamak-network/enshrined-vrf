package miner

import (
	"github.com/decred/dcrd/dcrec/secp256k1/v4"
)

// VRFConfig holds the configuration for the Enshrined VRF system.
// The sequencer uses this to compute VRF proofs during block building.
type VRFConfig struct {
	// Enabled indicates whether VRF block building is active.
	Enabled bool

	// PrivateKey is the sequencer's VRF private key for computing proofs.
	// This is only set in sequencer mode, never exposed to EVM execution.
	PrivateKey *secp256k1.PrivateKey
}

// DefaultVRFConfig returns a disabled VRF configuration.
func DefaultVRFConfig() VRFConfig {
	return VRFConfig{Enabled: false}
}
