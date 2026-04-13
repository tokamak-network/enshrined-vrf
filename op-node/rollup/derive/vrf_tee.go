package derive

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "github.com/tokamak-network/enshrined-vrf/vrf-enclave/proto"
)

// TEEVRFProver delegates VRF proof generation to a TEE enclave over gRPC.
// The secret key lives exclusively inside the enclave and is never exposed.
type TEEVRFProver struct {
	conn   *grpc.ClientConn
	client pb.VRFEnclaveClient
	pk     []byte // cached public key from enclave
}

// NewTEEVRFProver connects to a TEE enclave at the given gRPC endpoint
// and fetches the public key. The endpoint can be a Unix socket
// (unix:///var/run/vrf-enclave.sock) or TCP address (localhost:50051).
func NewTEEVRFProver(endpoint string) (*TEEVRFProver, error) {
	conn, err := grpc.NewClient(endpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to TEE enclave at %s: %w", endpoint, err)
	}

	client := pb.NewVRFEnclaveClient(conn)

	// Fetch and cache the public key at startup
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	resp, err := client.GetPublicKey(ctx, &pb.GetPublicKeyRequest{})
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to get public key from TEE enclave: %w", err)
	}

	if len(resp.PublicKey) != 33 {
		conn.Close()
		return nil, fmt.Errorf("TEE enclave returned invalid public key length: %d", len(resp.PublicKey))
	}

	return &TEEVRFProver{
		conn:   conn,
		client: client,
		pk:     resp.PublicKey,
	}, nil
}

func (t *TEEVRFProver) Prove(seed []byte) (beta [32]byte, pi [81]byte, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	resp, err := t.client.Prove(ctx, &pb.ProveRequest{Seed: seed})
	if err != nil {
		return beta, pi, fmt.Errorf("TEE enclave Prove failed: %w", err)
	}

	if len(resp.Beta) != 32 {
		return beta, pi, fmt.Errorf("TEE enclave returned invalid beta length: %d", len(resp.Beta))
	}
	if len(resp.Pi) != 81 {
		return beta, pi, fmt.Errorf("TEE enclave returned invalid pi length: %d", len(resp.Pi))
	}

	copy(beta[:], resp.Beta)
	copy(pi[:], resp.Pi)
	return beta, pi, nil
}

func (t *TEEVRFProver) PublicKey() []byte {
	return t.pk
}

// Close shuts down the gRPC connection to the TEE enclave.
func (t *TEEVRFProver) Close() error {
	return t.conn.Close()
}
