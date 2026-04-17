package enclave

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const sealedKeyFile = "vrf_sealed.key"

// SealedStorage persists the VRF secret key encrypted under a caller-supplied
// 32-byte seal key. In a real TEE deployment, the seal key must be derived
// from a platform primitive (SGX MRSIGNER, TDX REPORTDATA, SEV-SNP VMPCK) so
// it is bound to the enclave identity. Callers choose the key source at
// startup — this package does not pick one implicitly.
type SealedStorage struct {
	dir     string
	sealKey [32]byte
}

// NewSealedStorage creates a SealedStorage that persists to dir, encrypting
// with the given 32-byte sealKey. Use DevSealKeyFromHostname only in dev/test.
func NewSealedStorage(dir string, sealKey [32]byte) *SealedStorage {
	return &SealedStorage{dir: dir, sealKey: sealKey}
}

// Exists returns true if a sealed key file already exists.
func (s *SealedStorage) Exists() bool {
	_, err := os.Stat(filepath.Join(s.dir, sealedKeyFile))
	return err == nil
}

// Seal encrypts the secret key bytes and writes them to disk.
func (s *SealedStorage) Seal(skBytes []byte) error {
	aead, err := newAEAD(s.sealKey)
	if err != nil {
		return fmt.Errorf("seal: %w", err)
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

	aead, err := newAEAD(s.sealKey)
	if err != nil {
		return nil, fmt.Errorf("unseal: %w", err)
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

// DevSealKeyFromHostname derives a deterministic 32-byte seal key from the
// host's hostname. DEV/TEST ONLY: the hostname is guessable and provides no
// cryptographic isolation between enclave instances.
func DevSealKeyFromHostname() [32]byte {
	hostname, _ := os.Hostname()
	return sha256.Sum256([]byte("vrf-enclave-dev-seal-" + hostname))
}

// SealKeyFromHex parses a 64-character hex string as a 32-byte seal key.
func SealKeyFromHex(s string) ([32]byte, error) {
	var key [32]byte
	b, err := hex.DecodeString(s)
	if err != nil {
		return key, fmt.Errorf("seal key: invalid hex: %w", err)
	}
	if len(b) != 32 {
		return key, fmt.Errorf("seal key: want 32 bytes, got %d", len(b))
	}
	copy(key[:], b)
	return key, nil
}

func newAEAD(key [32]byte) (cipher.AEAD, error) {
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, fmt.Errorf("create cipher: %w", err)
	}
	return cipher.NewGCM(block)
}
