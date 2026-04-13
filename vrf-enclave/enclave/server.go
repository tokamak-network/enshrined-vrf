package enclave

import (
	"context"
	"crypto/rand"
	"fmt"
	"log"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tokamak-network/enshrined-vrf/crypto/ecvrf"
	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

// Server implements the VRFEnclave gRPC service.
// The secret key is held exclusively in this process's memory.
type Server struct {
	pb.UnimplementedVRFEnclaveServer

	sk *secp256k1.PrivateKey
	pk []byte // cached 33-byte compressed public key
}

// NewServer initializes the enclave server. It either unseals an existing
// key from storage or generates a fresh one and seals it.
func NewServer(storage *SealedStorage) (*Server, error) {
	var sk *secp256k1.PrivateKey

	if storage.Exists() {
		skBytes, err := storage.Unseal()
		if err != nil {
			return nil, fmt.Errorf("failed to unseal key: %w", err)
		}
		sk = secp256k1.PrivKeyFromBytes(skBytes)
		log.Println("Unsealed existing VRF key from sealed storage")
	} else {
		var err error
		sk, err = generateKey()
		if err != nil {
			return nil, fmt.Errorf("failed to generate key: %w", err)
		}
		skBytes := sk.Key.Bytes()
		if err := storage.Seal(skBytes[:]); err != nil {
			return nil, fmt.Errorf("failed to seal key: %w", err)
		}
		log.Println("Generated and sealed new VRF key")
	}

	pk := sk.PubKey().SerializeCompressed()
	log.Printf("VRF public key: %x", pk)

	return &Server{sk: sk, pk: pk}, nil
}

// NewServerFromKey creates a server from a pre-existing private key
// (for testing or migration from local mode).
func NewServerFromKey(sk *secp256k1.PrivateKey) *Server {
	return &Server{
		sk: sk,
		pk: sk.PubKey().SerializeCompressed(),
	}
}

func (s *Server) Prove(ctx context.Context, req *pb.ProveRequest) (*pb.ProveResponse, error) {
	if len(req.Seed) != 32 {
		return nil, status.Errorf(codes.InvalidArgument, "seed must be 32 bytes, got %d", len(req.Seed))
	}

	beta, pi, err := ecvrf.Prove(s.sk, req.Seed)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "VRF prove failed: %v", err)
	}

	return &pb.ProveResponse{
		Beta: beta[:],
		Pi:   pi[:],
	}, nil
}

func (s *Server) GetPublicKey(ctx context.Context, req *pb.GetPublicKeyRequest) (*pb.GetPublicKeyResponse, error) {
	return &pb.GetPublicKeyResponse{
		PublicKey: s.pk,
	}, nil
}

func (s *Server) GetAttestation(ctx context.Context, req *pb.GetAttestationRequest) (*pb.GetAttestationResponse, error) {
	// TODO(production): Generate a real TEE attestation report here:
	//   - SGX: sgx_create_report() → sgx_get_quote()
	//   - TDX: TDX.TDREPORT with challenge bound to REPORTDATA
	//   - SEV-SNP: SNP_GET_REPORT with challenge
	//
	// The report should bind the public key so a verifier can confirm
	// that this specific key lives inside a genuine enclave.
	return nil, status.Errorf(codes.Unimplemented, "attestation not yet implemented — requires TEE platform SDK")
}

func generateKey() (*secp256k1.PrivateKey, error) {
	seed := make([]byte, 32)
	if _, err := rand.Read(seed); err != nil {
		return nil, fmt.Errorf("crypto/rand: %w", err)
	}
	return secp256k1.PrivKeyFromBytes(seed), nil
}
