package main

import (
	"encoding/hex"
	"flag"
	"fmt"
	"log"
	"strings"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
)

func main() {
	skHex := flag.String("sk", "", "Hex-encoded secp256k1 private key (64 hex chars)")
	seedHex := flag.String("seed", "", "Hex-encoded 32-byte seed")
	flag.Parse()

	if *skHex == "" || *seedHex == "" {
		log.Fatal("Usage: vrf-prove -sk <hex> -seed <hex>")
	}

	// Parse private key
	trimmed := strings.TrimPrefix(*skHex, "0x")
	skBytes, err := hex.DecodeString(trimmed)
	if err != nil {
		log.Fatalf("Invalid sk hex: %v", err)
	}
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey().SerializeCompressed()

	// Parse seed
	seedTrimmed := strings.TrimPrefix(*seedHex, "0x")
	seed, err := hex.DecodeString(seedTrimmed)
	if err != nil {
		log.Fatalf("Invalid seed hex: %v", err)
	}
	if len(seed) != 32 {
		log.Fatalf("Seed must be 32 bytes, got %d", len(seed))
	}

	// Prove
	beta, pi, err := ecvrf.Prove(sk, seed)
	if err != nil {
		log.Fatalf("Prove failed: %v", err)
	}

	// Output
	fmt.Printf("pk=0x%x\n", pk)
	fmt.Printf("seed=0x%x\n", seed)
	fmt.Printf("beta=0x%x\n", beta)
	fmt.Printf("pi=0x%x\n", pi)
}
