package engine

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"

	"github.com/ethereum/go-ethereum/common"
)

func TestPayloadAttributesVRFJSONUsesHex(t *testing.T) {
	nonce := uint64(7)
	attrs := PayloadAttributes{
		Timestamp:             1,
		Random:                common.Hash{0x01},
		SuggestedFeeRecipient: common.Address{0x02},
		VRFPublicKey:          append([]byte{0x02}, bytes.Repeat([]byte{0x11}, 32)...),
		VRFSeed:               bytes.Repeat([]byte{0x22}, 32),
		VRFProofBeta:          bytes.Repeat([]byte{0x33}, 32),
		VRFProofPi:            bytes.Repeat([]byte{0x44}, 81),
		VRFNonce:              &nonce,
	}

	out, err := json.Marshal(attrs)
	if err != nil {
		t.Fatalf("marshal payload attrs: %v", err)
	}
	if strings.Contains(string(out), base64.StdEncoding.EncodeToString(attrs.VRFSeed)) {
		t.Fatalf("VRF seed was marshaled as base64: %s", out)
	}
	if !strings.Contains(string(out), `"vrfSeed":"0x2222222222222222222222222222222222222222222222222222222222222222"`) {
		t.Fatalf("VRF seed was not marshaled as hex: %s", out)
	}

	var decoded PayloadAttributes
	if err := json.Unmarshal(out, &decoded); err != nil {
		t.Fatalf("unmarshal payload attrs: %v", err)
	}
	if !bytes.Equal(decoded.VRFPublicKey, attrs.VRFPublicKey) {
		t.Fatalf("public key mismatch")
	}
	if !bytes.Equal(decoded.VRFSeed, attrs.VRFSeed) {
		t.Fatalf("seed mismatch")
	}
	if !bytes.Equal(decoded.VRFProofBeta, attrs.VRFProofBeta) {
		t.Fatalf("beta mismatch")
	}
	if !bytes.Equal(decoded.VRFProofPi, attrs.VRFProofPi) {
		t.Fatalf("proof mismatch")
	}
	if decoded.VRFNonce == nil || *decoded.VRFNonce != nonce {
		t.Fatalf("nonce mismatch")
	}
}
