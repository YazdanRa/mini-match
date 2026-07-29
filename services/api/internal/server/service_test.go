package server

import (
	"context"
	"errors"
	"net"
	"net/http"
	"testing"

	"connectrpc.com/connect"
	minimatchv1 "github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1"
	"github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1/minimatchv1connect"
	"github.com/YazdanRa/mini-match/services/api/internal/authn"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

type testVerifier map[string]string

func (v testVerifier) VerifyIDToken(_ context.Context, token string) (string, error) {
	uid, ok := v[token]
	if !ok {
		return "", errors.New("invalid token")
	}
	return uid, nil
}

func TestConnectAndGRPCKeepPicksPrivateUntilReveal(t *testing.T) {
	mux := http.NewServeMux()
	path, handler := minimatchv1connect.NewMiniMatchServiceHandler(
		New(game.NewMemoryRepository()),
		connect.WithInterceptors(authn.NewInterceptor(testVerifier{
			"host-token":     "maya",
			"player-token":   "liam",
			"intruder-token": "zoe",
		})),
	)
	mux.Handle(path, handler)

	ctx := context.Background()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	serverProtocols := new(http.Protocols)
	serverProtocols.SetHTTP1(true)
	serverProtocols.SetUnencryptedHTTP2(true)
	httpServer := &http.Server{Handler: mux, Protocols: serverProtocols}
	go func() {
		_ = httpServer.Serve(listener)
	}()
	t.Cleanup(func() {
		_ = httpServer.Shutdown(context.Background())
	})

	baseURL := "http://" + listener.Addr().String()
	connectClient := minimatchv1connect.NewMiniMatchServiceClient(http.DefaultClient, baseURL)
	clientProtocols := new(http.Protocols)
	clientProtocols.SetUnencryptedHTTP2(true)
	grpcClient := minimatchv1connect.NewMiniMatchServiceClient(
		&http.Client{Transport: &http.Transport{Protocols: clientProtocols}},
		baseURL,
		connect.WithGRPC(),
	)

	created, err := connectClient.CreateTable(ctx, authenticated(&minimatchv1.CreateTableRequest{
		Name:            "Friday",
		HostDisplayName: "Maya",
	}, "host-token"))
	if err != nil {
		t.Fatal(err)
	}
	if created.Msg.PlayerId != "maya" {
		t.Fatalf("host ID = %q, want verified UID", created.Msg.PlayerId)
	}
	joined, err := grpcClient.JoinTable(ctx, authenticated(&minimatchv1.JoinTableRequest{
		JoinCode:    created.Msg.Table.JoinCode,
		DisplayName: "Liam",
	}, "player-token"))
	if err != nil {
		t.Fatal(err)
	}
	tableID := created.Msg.Table.Id
	if _, err := connectClient.LockPick(ctx, authenticated(&minimatchv1.LockPickRequest{
		TableId:     tableID,
		PlayerId:    joined.Msg.PlayerId,
		Pick:        &minimatchv1.Pick{Value: 99},
		RoundNumber: 1,
	}, "host-token")); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("spoofed lock code = %v, want permission denied", connect.CodeOf(err))
	}
	if _, err := connectClient.LockPick(ctx, authenticated(&minimatchv1.LockPickRequest{
		TableId:     tableID,
		PlayerId:    created.Msg.PlayerId,
		Pick:        &minimatchv1.Pick{Value: 2},
		RoundNumber: 1,
	}, "host-token")); err != nil {
		t.Fatal(err)
	}
	if _, err := grpcClient.GetTable(ctx, authenticated(
		&minimatchv1.GetTableRequest{TableId: tableID},
		"intruder-token",
	)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("non-member read code = %v, want permission denied", connect.CodeOf(err))
	}
	beforeReveal, err := grpcClient.GetTable(ctx, authenticated(
		&minimatchv1.GetTableRequest{TableId: tableID},
		"player-token",
	))
	if err != nil {
		t.Fatal(err)
	}
	if beforeReveal.Msg.Table.LastResult != nil {
		t.Fatal("GetTable exposed selections before reveal")
	}
	if _, err := grpcClient.LockPick(ctx, authenticated(&minimatchv1.LockPickRequest{
		TableId:     tableID,
		PlayerId:    joined.Msg.PlayerId,
		Pick:        &minimatchv1.Pick{Value: 5},
		RoundNumber: 1,
	}, "player-token")); err != nil {
		t.Fatal(err)
	}
	revealed, err := connectClient.StartRound(ctx, authenticated(&minimatchv1.StartRoundRequest{
		TableId:      tableID,
		HostPlayerId: created.Msg.PlayerId,
		RoundNumber:  1,
	}, "host-token"))
	if err != nil {
		t.Fatal(err)
	}
	if got := len(revealed.Msg.Table.LastResult.GetSelections()); got != 2 {
		t.Fatalf("revealed selections = %d, want 2", got)
	}
	if got := revealed.Msg.Table.LastResult.GetWinnerPlayerId(); got != created.Msg.PlayerId {
		t.Fatalf("winner = %q, want host", got)
	}
}

func authenticated[T any](message *T, token string) *connect.Request[T] {
	request := connect.NewRequest(message)
	request.Header().Set("Authorization", "Bearer "+token)
	return request
}
