//go:build with_utls

package tls

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	stdtls "crypto/tls"
	"errors"
	"net"
	"slices"
	"strings"
	"testing"
	"time"

	utls "github.com/metacubex/utls"
)

func TestRealityKeyShareECDHEUsesMLKEMX25519Component(t *testing.T) {
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	got := realityKeyShareECDHE(&utls.KeySharePrivateKeys{MlkemEcdhe: key})
	if got != key {
		t.Fatal("expected REALITY to use the X25519 component of the hybrid key share")
	}
}

func TestRealityClientNegotiatesX25519MLKEM768(t *testing.T) {
	certificate, err := GenerateKeyPair(nil, nil, time.Now, "localhost")
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	serverErr := make(chan error, 1)
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			serverErr <- acceptErr
			return
		}
		defer conn.Close()
		serverConfig := &stdtls.Config{
			Certificates:     []stdtls.Certificate{*certificate},
			MinVersion:       stdtls.VersionTLS13,
			MaxVersion:       stdtls.VersionTLS13,
			CurvePreferences: []stdtls.CurveID{stdtls.X25519MLKEM768},
		}
		serverConfig.GetConfigForClient = func(hello *stdtls.ClientHelloInfo) (*stdtls.Config, error) {
			if !slices.Contains(hello.SupportedCurves, stdtls.X25519MLKEM768) {
				return nil, errors.New("client did not offer X25519MLKEM768")
			}
			return nil, nil
		}
		server := stdtls.Server(conn, serverConfig)
		serverErr <- server.Handshake()
	}()

	privateKey, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	client := realityClientForTest(ctx, privateKey.PublicKey().Bytes())
	_, err = client.ClientHandshake(ctx, conn)
	if err == nil || !strings.Contains(err.Error(), "x509") {
		// A normal TLS endpoint must complete the outer TLS handshake before
		// REALITY certificate verification fails.
		t.Fatalf("unexpected client handshake result: %v", err)
	}
	err = <-serverErr
	if err == nil || !strings.Contains(err.Error(), "bad certificate") {
		t.Fatalf("server did not complete X25519MLKEM768 handshake: %v", err)
	}
}

func realityClientForTest(ctx context.Context, publicKey []byte) *RealityClientConfig {
	uClient := &UTLSClientConfig{
		ctx:              ctx,
		config:           &utls.Config{ServerName: "localhost"},
		serverName:       "localhost",
		handshakeTimeout: 5 * time.Second,
		id:               utls.HelloChrome_Auto,
	}
	return &RealityClientConfig{
		ctx:       ctx,
		uClient:   uClient,
		publicKey: publicKey,
	}
}
