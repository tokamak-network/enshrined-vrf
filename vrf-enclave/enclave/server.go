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

// AttestationMode selects how GetAttestation responds. Callers pick the
// mode at server construction so an operator never accidentally ships a
// dev HMAC report from a production build.
type AttestationMode int

const (
	// AttestNone disables GetAttestation. Clients get FailedPrecondition.
	AttestNone AttestationMode = iota
	// AttestDev returns the HMAC-based dev report. Proves key possession
	// only — NOT that the code runs inside a secure enclave. Intended for
	// local/test use.
	AttestDev
)

// Server implements the VRFEnclave gRPC service.
// The secret key is held exclusively in this process's memory, ensuring
// unpredictability: the sequencer operator cannot access sk and therefore
// cannot predict future VRF outputs or manipulate randomness.
type Server struct {
	pb.UnimplementedVRFEnclaveServer

	sk         *secp256k1.PrivateKey
	pk         []byte // cached 33-byte compressed public key
	attestMode AttestationMode
}

// NewServer initializes the enclave server. It either unseals an existing
// key from storage or generates a fresh one and seals it.
func NewServer(storage *SealedStorage, attestMode AttestationMode) (*Server, error) {
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

	return &Server{sk: sk, pk: pk, attestMode: attestMode}, nil
}

// NewServerFromKey creates a server from a pre-existing private key
// (for testing or migration from local mode).
func NewServerFromKey(sk *secp256k1.PrivateKey, attestMode AttestationMode) *Server {
	return &Server{
		sk:         sk,
		pk:         sk.PubKey().SerializeCompressed(),
		attestMode: attestMode,
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

// Close zeros the secret key scalar in place. Safe to call once after the
// gRPC server has stopped serving — concurrent Prove/GetAttestation calls
// still holding s.sk would race.
func (s *Server) Close() error {
	if s.sk != nil {
		s.sk.Key.Zero()
		s.sk = nil
	}
	return nil
}

func (s *Server) GetAttestation(ctx context.Context, req *pb.GetAttestationRequest) (*pb.GetAttestationResponse, error) {
	switch s.attestMode {
	case AttestDev:
		// Dev HMAC report proves key possession but NOT that the code runs
		// inside a secure enclave. Production must select a platform mode
		// (SGX quote, TDX report, SEV-SNP report) once integrated.
		skBytes := s.sk.Key.Bytes()
		report := CreateDevAttestation(skBytes[:], s.pk, req.Challenge)
		return &pb.GetAttestationResponse{
			Report:    report,
			PublicKey: s.pk,
		}, nil
	case AttestNone:
		return nil, status.Error(codes.FailedPrecondition,
			"attestation disabled; start the enclave with an explicit attestation mode")
	default:
		return nil, status.Errorf(codes.Unimplemented,
			"attestation mode %d not supported", s.attestMode)
	}
}

func generateKey() (*secp256k1.PrivateKey, error) {
	seed := make([]byte, 32)
	if _, err := rand.Read(seed); err != nil {
		return nil, fmt.Errorf("crypto/rand: %w", err)
	}
	return secp256k1.PrivKeyFromBytes(seed), nil
}
