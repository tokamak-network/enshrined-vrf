package opnode

import (
	"fmt"

	"github.com/ethereum/go-ethereum/log"

	"github.com/ethereum-optimism/optimism/op-node/flags"
	"github.com/ethereum-optimism/optimism/op-node/rollup/derive"
	"github.com/ethereum-optimism/optimism/op-service/cliiface"
)

// NewVRFProver creates a VRFProver based on CLI flags.
// Returns nil if no VRF key or TEE endpoint is configured.
func NewVRFProver(ctx cliiface.Context, log log.Logger) (derive.VRFProver, error) {
	mode := ctx.String(flags.SequencerVRFModeFlag.Name)
	switch mode {
	case "local":
		hexKey := ctx.String(flags.SequencerVRFKeyFlag.Name)
		if hexKey == "" {
			return nil, nil
		}
		prover, err := derive.NewLocalVRFProver(hexKey)
		if err != nil {
			return nil, fmt.Errorf("failed to create local VRF prover: %w", err)
		}
		log.Info("Initialized local VRF prover for EnshrainedVRF")
		return prover, nil

	case "tee":
		endpoint := ctx.String(flags.SequencerVRFTEEEndpointFlag.Name)
		if endpoint == "" {
			return nil, fmt.Errorf("--sequencer.vrf-tee-endpoint is required when --sequencer.vrf-mode=tee")
		}
		prover, err := derive.NewTEEVRFProver(endpoint)
		if err != nil {
			return nil, fmt.Errorf("failed to create TEE VRF prover: %w", err)
		}
		log.Info("Initialized TEE VRF prover for EnshrainedVRF", "endpoint", endpoint)
		return prover, nil

	default:
		return nil, fmt.Errorf("unknown VRF mode %q (expected 'local' or 'tee')", mode)
	}
}
