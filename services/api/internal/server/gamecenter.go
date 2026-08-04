package server

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"time"

	minimatchv1 "github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1"
)

const gameBundleID = "com.yazdanra.minimatch"

var gameCenterHTTPClient = &http.Client{
	Timeout: 5 * time.Second,
	CheckRedirect: func(request *http.Request, via []*http.Request) error {
		if len(via) >= 3 {
			return errors.New("too many Game Center certificate redirects")
		}
		if request.URL.Scheme != "https" || !allowedCertificateHost(request.URL.Hostname()) {
			return errors.New("invalid Game Center public key redirect")
		}
		return nil
	},
}

func verifyGameCenterIdentity(
	ctx context.Context,
	identity *minimatchv1.GameCenterIdentity,
) (string, error) {
	if identity == nil {
		return "", nil
	}
	if identity.GetTeamPlayerId() == "" ||
		len(identity.GetSignature()) == 0 ||
		len(identity.GetSalt()) == 0 ||
		identity.GetTimestamp() > math.MaxInt64 {
		return "", errors.New("incomplete Game Center identity")
	}
	publicKeyURL, err := url.Parse(identity.GetPublicKeyUrl())
	if err != nil || publicKeyURL.Scheme != "https" || publicKeyURL.Hostname() != "static.gc.apple.com" {
		return "", errors.New("invalid Game Center public key URL")
	}
	signedAt := time.UnixMilli(int64(identity.GetTimestamp()))
	age := time.Since(signedAt)
	if age < -time.Minute || age > 5*time.Minute {
		return "", errors.New("expired Game Center identity")
	}

	certificate, err := downloadCertificate(ctx, publicKeyURL)
	if err != nil {
		return "", err
	}
	intermediates := x509.NewCertPool()
	for _, issuerURL := range certificate.IssuingCertificateURL {
		parsed, err := url.Parse(issuerURL)
		if err != nil || parsed.Hostname() != "cacerts.digicert.com" {
			return "", errors.New("invalid Game Center certificate issuer")
		}
		parsed.Scheme = "https"
		issuer, err := downloadCertificate(ctx, parsed)
		if err != nil {
			return "", err
		}
		intermediates.AddCert(issuer)
	}
	if _, err := certificate.Verify(x509.VerifyOptions{
		Intermediates: intermediates,
		KeyUsages:     []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return "", fmt.Errorf("verify Game Center public key: %w", err)
	}
	publicKey, ok := certificate.PublicKey.(*rsa.PublicKey)
	if !ok {
		return "", errors.New("Game Center public key is not RSA")
	}

	if err := verifyGameCenterSignature(
		publicKey,
		identity,
	); err != nil {
		return "", errors.New("invalid Game Center identity signature")
	}
	return identity.GetTeamPlayerId(), nil
}

func allowedCertificateHost(host string) bool {
	return host == "static.gc.apple.com" || host == "cacerts.digicert.com"
}

func downloadCertificate(ctx context.Context, certificateURL *url.URL) (*x509.Certificate, error) {
	if certificateURL.Scheme != "https" || !allowedCertificateHost(certificateURL.Hostname()) {
		return nil, errors.New("invalid Game Center certificate URL")
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, certificateURL.String(), nil)
	if err != nil {
		return nil, err
	}
	response, err := gameCenterHTTPClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("download Game Center certificate: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download Game Center certificate: HTTP %d", response.StatusCode)
	}
	der, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("read Game Center certificate: %w", err)
	}
	certificate, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, fmt.Errorf("parse Game Center certificate: %w", err)
	}
	return certificate, nil
}

func verifyGameCenterSignature(
	publicKey *rsa.PublicKey,
	identity *minimatchv1.GameCenterIdentity,
) error {
	hash := sha256.New()
	hash.Write([]byte(identity.GetTeamPlayerId()))
	hash.Write([]byte(gameBundleID))
	var timestamp [8]byte
	binary.BigEndian.PutUint64(timestamp[:], identity.GetTimestamp())
	hash.Write(timestamp[:])
	hash.Write(identity.GetSalt())
	return rsa.VerifyPKCS1v15(
		publicKey,
		crypto.SHA256,
		hash.Sum(nil),
		identity.GetSignature(),
	)
}
