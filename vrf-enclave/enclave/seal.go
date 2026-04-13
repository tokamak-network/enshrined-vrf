package enclave

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const sealedKeyFile = "vrf_sealed.key"

// SealedStorage handles persisting the VRF secret key in encrypted form.
// In a real TEE deployment, sealing uses a platform-derived key (e.g. SGX
// MRSIGNER-based seal key). This implementation uses a file-based sealing
// key as a development placeholder — replace deriveSealKey() with the
// platform-specific sealing primitive for production.
type SealedStorage struct {
	dir string
}

// NewSealedStorage creates a SealedStorage that persists to the given directory.
func NewSealedStorage(dir string) *SealedStorage {
	return &SealedStorage{dir: dir}
}

// Exists returns true if a sealed key file already exists.
func (s *SealedStorage) Exists() bool {
	_, err := os.Stat(filepath.Join(s.dir, sealedKeyFile))
	return err == nil
}

// Seal encrypts the secret key bytes and writes them to disk.
func (s *SealedStorage) Seal(skBytes []byte) error {
	sealKey := deriveSealKey()
	block, err := aes.NewCipher(sealKey)
	if err != nil {
		return fmt.Errorf("seal: create cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return fmt.Errorf("seal: create GCM: %w", err)
	}

	nonce := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return fmt.Errorf("seal: generate nonce: %w", err)
	}

	ciphertext := aead.Seal(nonce, nonce, skBytes, nil)

	if err := os.MkdirAll(s.dir, 0700); err != nil {
		return fmt.Errorf("seal: create dir: %w", err)
	}
	path := filepath.Join(s.dir, sealedKeyFile)
	if err := os.WriteFile(path, ciphertext, 0600); err != nil {
		return fmt.Errorf("seal: write file: %w", err)
	}
	return nil
}

// Unseal reads and decrypts the secret key from disk.
func (s *SealedStorage) Unseal() ([]byte, error) {
	path := filepath.Join(s.dir, sealedKeyFile)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("unseal: read file: %w", err)
	}

	sealKey := deriveSealKey()
	block, err := aes.NewCipher(sealKey)
	if err != nil {
		return nil, fmt.Errorf("unseal: create cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("unseal: create GCM: %w", err)
	}

	nonceSize := aead.NonceSize()
	if len(data) < nonceSize {
		return nil, errors.New("unseal: ciphertext too short")
	}

	nonce, ciphertext := data[:nonceSize], data[nonceSize:]
	plaintext, err := aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("unseal: decrypt: %w", err)
	}
	return plaintext, nil
}

// deriveSealKey returns the 32-byte key used for sealing.
//
// TODO(production): Replace this with a TEE platform-specific seal key:
//   - SGX: Use sgx_seal_data() with MRSIGNER policy
//   - TDX: Use TDX.REPORTDATA-bound key via KDF
//   - SEV-SNP: Use VMPCK-derived key
//
// The current implementation derives from a machine-local identity
// (hostname) — suitable ONLY for development and testing.
func deriveSealKey() []byte {
	hostname, _ := os.Hostname()
	h := sha256.Sum256([]byte("vrf-enclave-dev-seal-" + hostname))
	return h[:]
}
