package miner

// VRFConfig is kept for backward compatibility but is no longer used.
// VRF proof computation has moved to op-node, which holds the sequencer's
// VRF private key. VRF proofs are passed to op-geth via PayloadAttributes
// in the Engine API.
type VRFConfig struct {
	Enabled bool
}

// DefaultVRFConfig returns a disabled VRF configuration.
func DefaultVRFConfig() VRFConfig {
	return VRFConfig{Enabled: false}
}
