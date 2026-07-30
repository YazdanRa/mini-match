package server

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/binary"
	"testing"

	minimatchv1 "github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1"
)

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
