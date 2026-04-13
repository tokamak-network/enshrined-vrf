package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"

	"github.com/tokamak-network/enshrined-vrf/vrf-enclave/enclave"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

func main() {
	listen := flag.String("listen", "localhost:50051", "gRPC listen address (TCP or unix:///path/to/sock)")
	sealDir := flag.String("seal-dir", "./sealed", "Directory for sealed key storage")
	flag.Parse()

	storage := enclave.NewSealedStorage(*sealDir)
	srv, err := enclave.NewServer(storage)
	if err != nil {
		log.Fatalf("Failed to initialize enclave server: %v", err)
	}

	lis, err := listen2(*listen)
	if err != nil {
		log.Fatalf("Failed to listen on %s: %v", *listen, err)
	}

	grpcServer := grpc.NewServer()
	pb.RegisterVRFEnclaveServer(grpcServer, srv)

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

func listen2(addr string) (net.Listener, error) {
	const unixPrefix = "unix://"
	if len(addr) > len(unixPrefix) && addr[:len(unixPrefix)] == unixPrefix {
		sockPath := addr[len(unixPrefix):]
		// Remove stale socket file if it exists
		os.Remove(sockPath)
		return net.Listen("unix", sockPath)
	}
	if _, err := fmt.Sscanf(addr, "%s", &addr); err == nil {
		return net.Listen("tcp", addr)
	}
	return net.Listen("tcp", addr)
}
