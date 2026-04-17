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
	devSeal := flag.Bool("dev-seal", false, "Derive seal key from hostname (INSECURE — dev/test only)")
	flag.Parse()

	sealKey, err := resolveSealKey(*devSeal)
	if err != nil {
		log.Fatalf("seal key: %v", err)
	}

	storage := enclave.NewSealedStorage(*sealDir, sealKey)
	srv, err := enclave.NewServer(storage)
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

// resolveSealKey picks the seal key source. Exactly one of VRF_ENCLAVE_SEAL_KEY
// (hex-encoded 32 bytes) or the --dev-seal flag must be set — there is no
// implicit fallback, so a misconfigured deployment fails loudly instead of
// silently using a predictable key.
func resolveSealKey(devSeal bool) ([32]byte, error) {
	hex := os.Getenv("VRF_ENCLAVE_SEAL_KEY")
	switch {
	case hex != "" && devSeal:
		return [32]byte{}, fmt.Errorf("set either VRF_ENCLAVE_SEAL_KEY or --dev-seal, not both")
	case hex != "":
		return enclave.SealKeyFromHex(hex)
	case devSeal:
		log.Printf("WARNING: --dev-seal in use; seal key derived from hostname is NOT production-safe")
		return enclave.DevSealKeyFromHostname(), nil
	default:
		return [32]byte{}, fmt.Errorf("no seal key: set VRF_ENCLAVE_SEAL_KEY (hex 32B) or pass --dev-seal")
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
