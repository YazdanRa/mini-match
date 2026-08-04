package server

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"net/http"
	"testing"
	"time"

	minimatchv1 "github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1"
)

func TestVerifyGameCenterIdentityRejectsInvalidPreflight(t *testing.T) {
	now := uint64(time.Now().UnixMilli())
	identity := func(publicKeyURL string, timestamp uint64) *minimatchv1.GameCenterIdentity {
		return &minimatchv1.GameCenterIdentity{
			TeamPlayerId: "team-player",
			PublicKeyUrl: publicKeyURL,
			Signature:    []byte("signature"),
			Salt:         []byte("salt"),
			Timestamp:    timestamp,
		}
	}
	tests := []struct {
		name     string
		identity *minimatchv1.GameCenterIdentity
		wantErr  string
	}{
		{name: "missing", identity: nil},
		{name: "incomplete", identity: &minimatchv1.GameCenterIdentity{}, wantErr: "incomplete Game Center identity"},
		{name: "non-Apple host", identity: identity("https://example.com/key", now), wantErr: "invalid Game Center public key URL"},
		{name: "non-HTTPS URL", identity: identity("http://static.gc.apple.com/key", now), wantErr: "invalid Game Center public key URL"},
		{name: "expired", identity: identity("https://static.gc.apple.com/key", now-uint64((6*time.Minute)/time.Millisecond)), wantErr: "expired Game Center identity"},
	}

	transport := &rejectNetworkTransport{}
	originalClient := gameCenterHTTPClient
	gameCenterHTTPClient = &http.Client{Transport: transport}
	t.Cleanup(func() { gameCenterHTTPClient = originalClient })

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := verifyGameCenterIdentity(context.Background(), test.identity)
			if got != "" {
				t.Fatalf("identity = %q, want empty", got)
			}
			if test.wantErr == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
			} else if err == nil || err.Error() != test.wantErr {
				t.Fatalf("error = %v, want %q", err, test.wantErr)
			}
			if transport.called {
				t.Fatal("preflight validation made a network request")
			}
		})
	}
}

func TestGameCenterIdentitySignature(t *testing.T) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	identity := &minimatchv1.GameCenterIdentity{
		TeamPlayerId: "team-player",
		Salt:         []byte("salt"),
		Timestamp:    1_234,
	}
	hash := sha256.New()
	hash.Write([]byte(identity.TeamPlayerId))
	hash.Write([]byte(gameBundleID))
	var timestamp [8]byte
	binary.BigEndian.PutUint64(timestamp[:], identity.Timestamp)
	hash.Write(timestamp[:])
	hash.Write(identity.Salt)
	identity.Signature, err = rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, hash.Sum(nil))
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyGameCenterSignature(&privateKey.PublicKey, identity); err != nil {
		t.Fatalf("valid signature rejected: %v", err)
	}
	identity.TeamPlayerId = "another-player"
	if err := verifyGameCenterSignature(&privateKey.PublicKey, identity); err == nil {
		t.Fatal("signature accepted for another player")
	}
}

type rejectNetworkTransport struct {
	called bool
}

func (transport *rejectNetworkTransport) RoundTrip(*http.Request) (*http.Response, error) {
	transport.called = true
	return nil, errors.New("unexpected network request")
}
