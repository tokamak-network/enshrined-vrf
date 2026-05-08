package main

import (
	"bytes"
	"context"
	"net"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"

	"github.com/tokamak-network/enshrined-vrf/vrf-enclave/enclave"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

func TestParseSeed(t *testing.T) {
	seed, err := parseSeed("0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	if err != nil {
		t.Fatalf("parseSeed: %v", err)
	}
	if len(seed) != 32 || seed[0] != 0x00 || seed[31] != 0x1f {
		t.Fatalf("unexpected seed: %x", seed)
	}

	if _, err := parseSeed("0x01"); err == nil {
		t.Fatal("expected short seed to fail")
	}
}

func TestRunTEEPublicKeyOnly(t *testing.T) {
	endpoint, dialer := startBufconnEnclave(t)

	var out bytes.Buffer
	err := runTEE(&out, endpoint, "", true, false, "raw", "", time.Second,
		grpc.WithContextDialer(dialer),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("runTEE: %v", err)
	}

	got := strings.TrimSpace(out.String())
	if !regexp.MustCompile(`^pk=0x[0-9a-f]{66}$`).MatchString(got) {
		t.Fatalf("unexpected output: %q", got)
	}
}

func TestRunTEEProofOutput(t *testing.T) {
	endpoint, dialer := startBufconnEnclave(t)
	seed := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

	var out bytes.Buffer
	err := runTEE(&out, endpoint, seed, false, false, "raw", "", time.Second,
		grpc.WithContextDialer(dialer),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("runTEE: %v", err)
	}

	got := out.String()
	for name, pattern := range map[string]string{
		"pk":   `(?m)^pk=0x[0-9a-f]{66}$`,
		"seed": `(?m)^seed=0x[0-9a-f]{64}$`,
		"beta": `(?m)^beta=0x[0-9a-f]{64}$`,
		"pi":   `(?m)^pi=0x[0-9a-f]{162}$`,
	} {
		if !regexp.MustCompile(pattern).MatchString(got) {
			t.Fatalf("missing %s output in:\n%s", name, got)
		}
	}
}

func TestRunTEEDevAttestationOutput(t *testing.T) {
	endpoint, dialer := startBufconnEnclaveWithMode(t, enclave.AttestDev)
	challenge := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

	var out bytes.Buffer
	err := runTEE(&out, endpoint, "", true, true, "dev", challenge, time.Second,
		grpc.WithContextDialer(dialer),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("runTEE: %v", err)
	}

	got := out.String()
	for name, pattern := range map[string]string{
		"pk":                    `(?m)^pk=0x[0-9a-f]{66}$`,
		"attestation_mode":      `(?m)^attestation_mode=dev$`,
		"attestation_challenge": `(?m)^attestation_challenge=0x[0-9a-f]{64}$`,
		"attestation_pk":        `(?m)^attestation_pk=0x[0-9a-f]{66}$`,
		"attestation_report":    `(?m)^attestation_report=0x[0-9a-f]{130}$`,
	} {
		if !regexp.MustCompile(pattern).MatchString(got) {
			t.Fatalf("missing %s output in:\n%s", name, got)
		}
	}
}

func TestRunTEEAttestationDisabledFails(t *testing.T) {
	endpoint, dialer := startBufconnEnclave(t)
	var out bytes.Buffer
	err := runTEE(&out, endpoint, "", true, true, "raw", strings.Repeat("00", 32), time.Second,
		grpc.WithContextDialer(dialer),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err == nil {
		t.Fatal("expected disabled attestation to fail")
	}
	if !strings.Contains(err.Error(), "get TEE attestation") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func startBufconnEnclave(t *testing.T) (string, func(context.Context, string) (net.Conn, error)) {
	return startBufconnEnclaveWithMode(t, enclave.AttestNone)
}

func startBufconnEnclaveWithMode(t *testing.T, attestMode enclave.AttestationMode) (string, func(context.Context, string) (net.Conn, error)) {
	t.Helper()

	skBytes := bytes.Repeat([]byte{0x42}, 32)
	srv := enclave.NewServerFromKey(secp256k1.PrivKeyFromBytes(skBytes), attestMode)

	lis := bufconn.Listen(1024 * 1024)
	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)
	go func() {
		_ = grpcServer.Serve(lis)
	}()
	t.Cleanup(func() {
		grpcServer.Stop()
		_ = lis.Close()
	})

	dialer := func(context.Context, string) (net.Conn, error) {
		return lis.Dial()
	}
	return "passthrough:///bufnet", dialer
}
