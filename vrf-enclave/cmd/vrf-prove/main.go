package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
	"github.com/tokamak-network/enshrined-vrf/vrf-enclave/enclave"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	skHex := flag.String("sk", "", "Hex-encoded secp256k1 private key (64 hex chars)")
	seedHex := flag.String("seed", "", "Hex-encoded 32-byte seed")
	teeEndpoint := flag.String("tee-endpoint", "", "TEE enclave gRPC endpoint (e.g. localhost:50051 or unix:///var/run/vrf-enclave.sock)")
	publicKeyOnly := flag.Bool("public-key-only", false, "Print only pk=... without requiring a seed or proof")
	attest := flag.Bool("attest", false, "Fetch and print TEE attestation report")
	attestationMode := flag.String("attestation-mode", "raw", "Attestation check mode for -attest: raw | dev")
	attestationChallenge := flag.String("attestation-challenge", "", "Hex-encoded 32-byte attestation challenge (default: random)")
	timeout := flag.Duration("timeout", 10*time.Second, "TEE RPC timeout")
	flag.Parse()

	if *teeEndpoint != "" {
		if err := runTEE(os.Stdout, *teeEndpoint, *seedHex, *publicKeyOnly, *attest, *attestationMode, *attestationChallenge, *timeout); err != nil {
			log.Fatal(err)
		}
		return
	}

	if *skHex == "" {
		log.Fatal("Usage: vrf-prove -sk <hex> [-seed <hex> | -public-key-only] or vrf-prove -tee-endpoint <endpoint> [-seed <hex> | -public-key-only]")
	}

	// Parse private key
	trimmed := strings.TrimPrefix(*skHex, "0x")
	skBytes, err := hex.DecodeString(trimmed)
	if err != nil {
		log.Fatalf("Invalid sk hex: %v", err)
	}
	sk := secp256k1.PrivKeyFromBytes(skBytes)
	pk := sk.PubKey().SerializeCompressed()

	if *publicKeyOnly {
		fmt.Printf("pk=0x%x\n", pk)
		return
	}

	if *seedHex == "" {
		log.Fatal("seed is required unless -public-key-only is set")
	}

	// Parse seed
	seed, err := parseSeed(*seedHex)
	if err != nil {
		log.Fatal(err)
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

func runTEE(w io.Writer, endpoint string, seedHex string, publicKeyOnly bool, attest bool, attestationMode string, attestationChallenge string, timeout time.Duration, dialOptions ...grpc.DialOption) error {
	if len(dialOptions) == 0 {
		dialOptions = []grpc.DialOption{grpc.WithTransportCredentials(insecure.NewCredentials())}
	}
	conn, err := grpc.NewClient(endpoint, dialOptions...)
	if err != nil {
		return fmt.Errorf("connect TEE enclave: %w", err)
	}
	defer conn.Close()

	client := pb.NewVRFEnclaveClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	pkResp, err := client.GetPublicKey(ctx, &pb.GetPublicKeyRequest{})
	if err != nil {
		return fmt.Errorf("get TEE public key: %w", err)
	}
	if len(pkResp.PublicKey) != 33 {
		return fmt.Errorf("TEE public key must be 33 bytes, got %d", len(pkResp.PublicKey))
	}
	fmt.Fprintf(w, "pk=0x%x\n", pkResp.PublicKey)
	if attest {
		if err := runTEEAttestation(w, client, pkResp.PublicKey, attestationMode, attestationChallenge, timeout); err != nil {
			return err
		}
		if publicKeyOnly || seedHex == "" {
			return nil
		}
	}
	if publicKeyOnly {
		return nil
	}
	if seedHex == "" {
		return fmt.Errorf("seed is required unless -public-key-only is set")
	}

	seed, err := parseSeed(seedHex)
	if err != nil {
		return err
	}
	ctx, cancel = context.WithTimeout(context.Background(), timeout)
	defer cancel()
	proofResp, err := client.Prove(ctx, &pb.ProveRequest{Seed: seed})
	if err != nil {
		return fmt.Errorf("TEE prove: %w", err)
	}
	if len(proofResp.Beta) != 32 {
		return fmt.Errorf("TEE beta must be 32 bytes, got %d", len(proofResp.Beta))
	}
	if len(proofResp.Pi) != 81 {
		return fmt.Errorf("TEE pi must be 81 bytes, got %d", len(proofResp.Pi))
	}
	fmt.Fprintf(w, "seed=0x%x\n", seed)
	fmt.Fprintf(w, "beta=0x%x\n", proofResp.Beta)
	fmt.Fprintf(w, "pi=0x%x\n", proofResp.Pi)
	return nil
}

func runTEEAttestation(w io.Writer, client pb.VRFEnclaveClient, expectedPK []byte, attestationMode string, attestationChallenge string, timeout time.Duration) error {
	challenge, err := parseChallenge(attestationChallenge)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	resp, err := client.GetAttestation(ctx, &pb.GetAttestationRequest{Challenge: challenge})
	if err != nil {
		return fmt.Errorf("get TEE attestation: %w", err)
	}
	if len(resp.PublicKey) != 33 {
		return fmt.Errorf("TEE attestation public key must be 33 bytes, got %d", len(resp.PublicKey))
	}
	if !bytes.Equal(resp.PublicKey, expectedPK) {
		return fmt.Errorf("TEE attestation public key does not match GetPublicKey response")
	}
	if len(resp.Report) == 0 {
		return fmt.Errorf("TEE attestation report is empty")
	}
	switch attestationMode {
	case "raw":
	case "dev":
		if err := enclave.VerifyDevAttestation(resp.Report, challenge, expectedPK); err != nil {
			return fmt.Errorf("verify dev attestation: %w", err)
		}
	default:
		return fmt.Errorf("unsupported attestation mode %q (want raw | dev)", attestationMode)
	}
	fmt.Fprintf(w, "attestation_mode=%s\n", attestationMode)
	fmt.Fprintf(w, "attestation_challenge=0x%x\n", challenge)
	fmt.Fprintf(w, "attestation_pk=0x%x\n", resp.PublicKey)
	fmt.Fprintf(w, "attestation_report=0x%x\n", resp.Report)
	return nil
}

func parseSeed(seedHex string) ([]byte, error) {
	seedTrimmed := strings.TrimPrefix(seedHex, "0x")
	seed, err := hex.DecodeString(seedTrimmed)
	if err != nil {
		return nil, fmt.Errorf("invalid seed hex: %w", err)
	}
	if len(seed) != 32 {
		return nil, fmt.Errorf("seed must be 32 bytes, got %d", len(seed))
	}
	return seed, nil
}

func parseChallenge(challengeHex string) ([]byte, error) {
	if challengeHex == "" {
		challenge := make([]byte, 32)
		if _, err := rand.Read(challenge); err != nil {
			return nil, fmt.Errorf("generate attestation challenge: %w", err)
		}
		return challenge, nil
	}
	trimmed := strings.TrimPrefix(challengeHex, "0x")
	challenge, err := hex.DecodeString(trimmed)
	if err != nil {
		return nil, fmt.Errorf("invalid attestation challenge hex: %w", err)
	}
	if len(challenge) != 32 {
		return nil, fmt.Errorf("attestation challenge must be 32 bytes, got %d", len(challenge))
	}
	return challenge, nil
}
