package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/tokamak-network/enshrined-vrf/vrf-enclave/enclave"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

func main() {
	listen := flag.String("listen", "localhost:50051", "gRPC listen address (TCP or unix:///path/to/sock)")
	sealDir := flag.String("seal-dir", "./sealed", "Directory for sealed key storage")
	sealKeyFile := flag.String("seal-key-file", "", "Path to a file containing a hex-encoded 32-byte seal key")
	devSeal := flag.Bool("dev-seal", false, "Derive seal key from hostname (INSECURE — dev/test only)")
	attestFlag := flag.String("attestation", "none", "Attestation mode: none | dev (platform modes not yet implemented)")
	flag.Parse()

	sealKey, err := resolveSealKey(*sealKeyFile, *devSeal)
	if err != nil {
		log.Fatalf("seal key: %v", err)
	}

	attestMode, err := parseAttestationMode(*attestFlag)
	if err != nil {
		log.Fatalf("attestation: %v", err)
	}

	storage := enclave.NewSealedStorage(*sealDir, sealKey)
	srv, err := enclave.NewServer(storage, attestMode)
	if err != nil {
		log.Fatalf("Failed to initialize enclave server: %v", err)
	}

	lis, err := listenAddr(*listen)
	if err != nil {
		log.Fatalf("Failed to listen on %s: %v", *listen, err)
	}

	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)
	reflection.Register(grpcServer)

	// Graceful shutdown on SIGINT/SIGTERM
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		sig := <-sigCh
		log.Printf("Received %v, shutting down gracefully...", sig)
		grpcServer.GracefulStop()
	}()

	log.Printf("VRF enclave server listening on %s", *listen)
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("gRPC server error: %v", err)
	}
}

// resolveSealKey picks the seal key source. Exactly one of --seal-key-file,
// VRF_ENCLAVE_SEAL_KEY, or --dev-seal must be set — there is no implicit
// fallback, so a misconfigured deployment fails loudly instead of silently
// using a predictable key. The file form is preferred in production because
// file permissions bind the secret to a user and avoid env-var leakage into
// process listings.
func resolveSealKey(keyFile string, devSeal bool) ([32]byte, error) {
	envHex := os.Getenv("VRF_ENCLAVE_SEAL_KEY")
	sources := 0
	for _, set := range []bool{keyFile != "", envHex != "", devSeal} {
		if set {
			sources++
		}
	}
	switch {
	case sources > 1:
		return [32]byte{}, fmt.Errorf("pick exactly one of --seal-key-file, VRF_ENCLAVE_SEAL_KEY, or --dev-seal")
	case keyFile != "":
		return enclave.SealKeyFromFile(keyFile)
	case envHex != "":
		return enclave.SealKeyFromHex(envHex)
	case devSeal:
		log.Printf("WARNING: --dev-seal in use; seal key derived from hostname is NOT production-safe")
		return enclave.DevSealKeyFromHostname(), nil
	default:
		return [32]byte{}, fmt.Errorf("no seal key: pass --seal-key-file, set VRF_ENCLAVE_SEAL_KEY, or use --dev-seal")
	}
}

// parseAttestationMode maps a CLI string to the enclave AttestationMode.
// Dev mode prints a warning so an operator who flips it on by accident sees
// that the enclave is returning HMAC reports, not a real TEE quote.
func parseAttestationMode(s string) (enclave.AttestationMode, error) {
	switch s {
	case "none":
		return enclave.AttestNone, nil
	case "dev":
		log.Printf("WARNING: --attestation=dev returns HMAC reports; NOT a real TEE quote")
		return enclave.AttestDev, nil
	default:
		return enclave.AttestNone, fmt.Errorf("unknown attestation mode %q (want none | dev)", s)
	}
}

// listenAddr opens a listener for either a unix socket (unix:///path) or a
// TCP address (host:port). For unix sockets it clears any stale socket file.
func listenAddr(addr string) (net.Listener, error) {
	if sockPath, ok := strings.CutPrefix(addr, "unix://"); ok {
		os.Remove(sockPath)
		return net.Listen("unix", sockPath)
	}
	return net.Listen("tcp", addr)
}
