package server

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

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

type revealTrackingRepository struct {
	game.Repository
	reveals int
}

func (r *revealTrackingRepository) RevealRound(
	ctx context.Context,
	id string,
	reveal func(*game.Table) error,
) (*game.Table, error) {
	r.reveals++
	return r.Repository.RevealRound(ctx, id, reveal)
}

func TestPartyCodeMatchesGameKitFormat(t *testing.T) {
	for range 100 {
		code, err := partyCode()
		if err != nil {
			t.Fatal(err)
		}
		if !validPartyCode(code) {
			t.Fatalf("partyCode() = %q, want a valid GameKit party code", code)
		}
	}
	for _, code := range []string{"", "ABCD-EF12", "2345CFGH", "2345-CFG!"} {
		if validPartyCode(code) {
			t.Fatalf("validPartyCode(%q) = true, want false", code)
		}
	}
	for _, code := range []string{"23-CF", "234-CFG", "0123-4567"} {
		if !validPartyCode(code) {
			t.Fatalf("validPartyCode(%q) = false, want true", code)
		}
	}
}

func TestJoinTableEnforcesLiveGameCenterIdentityOwnership(t *testing.T) {
	now := time.Date(2026, time.August, 3, 12, 0, 0, 0, time.UTC)
	service := &Service{now: func() time.Time { return now }}

	t.Run("live duplicate", func(t *testing.T) {
		repository := game.NewMemoryRepository()
		table, _ := game.NewTable("live", "Friday", "LIVE", "maya", "Maya", "fox")
		_ = table.SetGameCenterID("maya", "game-center-player")
		_ = table.RefreshPresence("maya", now, playerPresenceDuration)
		if err := repository.Create(context.Background(), table); err != nil {
			t.Fatal(err)
		}

		_, err := repository.Update(context.Background(), table.ID, func(next *game.Table) error {
			return service.joinTable(next, "zoe", "Zoe", "owl", "game-center-player")
		})
		if !errors.Is(err, game.ErrAlreadyExists) {
			t.Fatalf("duplicate identity error = %v, want ErrAlreadyExists", err)
		}
		stored, _ := repository.Get(context.Background(), table.ID)
		if len(stored.Players) != 1 || stored.Players[0].ID != "maya" {
			t.Fatalf("rejected join changed table players: %#v", stored.Players)
		}
	})

	t.Run("expired membership", func(t *testing.T) {
		repository := game.NewMemoryRepository()
		table, _ := game.NewTable("expired", "Friday", "EXPIRED", "maya", "Maya", "fox")
		_ = table.SetGameCenterID("maya", "game-center-player")
		_ = table.RefreshPresence(
			"maya",
			now.Add(-playerPresenceDuration-time.Second),
			playerPresenceDuration,
		)
		if err := repository.Create(context.Background(), table); err != nil {
			t.Fatal(err)
		}

		updated, err := repository.Update(context.Background(), table.ID, func(next *game.Table) error {
			return service.joinTable(next, "zoe", "Zoe", "owl", "game-center-player")
		})
		if err != nil {
			t.Fatal(err)
		}
		if len(updated.Players) != 1 || updated.Players[0].ID != "zoe" ||
			updated.Players[0].GameCenterID != "game-center-player" {
			t.Fatalf("reclaimed table players: %#v", updated.Players)
		}
	})
}

func TestConnectAndGRPCKeepPicksPrivateUntilReveal(t *testing.T) {
	repository := &revealTrackingRepository{Repository: game.NewMemoryRepository()}
	mux := http.NewServeMux()
	path, handler := minimatchv1connect.NewMiniMatchServiceHandler(
		New(repository),
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
		HostAvatar:      "fox",
	}, "host-token"))
	if err != nil {
		t.Fatal(err)
	}
	if created.Msg.PlayerId != "maya" {
		t.Fatalf("host ID = %q, want verified UID", created.Msg.PlayerId)
	}
	if !validPartyCode(created.Msg.Table.JoinCode) {
		t.Fatalf("join code = %q, want GameKit-compatible party code", created.Msg.Table.JoinCode)
	}
	if _, err := connectClient.CreateTable(ctx, authenticated(&minimatchv1.CreateTableRequest{
		Name:            "Duplicate",
		HostDisplayName: "Maya",
		HostAvatar:      "fox",
		JoinCode:        created.Msg.Table.JoinCode,
	}, "host-token")); connect.CodeOf(err) != connect.CodeAlreadyExists {
		t.Fatalf("duplicate party code = %v, want already exists", connect.CodeOf(err))
	}
	joined, err := grpcClient.JoinTable(ctx, authenticated(&minimatchv1.JoinTableRequest{
		JoinCode:    created.Msg.Table.JoinCode,
		DisplayName: "Liam",
		Avatar:      "owl",
	}, "player-token"))
	if err != nil {
		t.Fatal(err)
	}
	resumed, err := grpcClient.JoinTable(ctx, authenticated(&minimatchv1.JoinTableRequest{
		JoinCode:    created.Msg.Table.JoinCode,
		DisplayName: "Liam",
		Avatar:      "owl",
	}, "player-token"))
	if err != nil {
		t.Fatalf("same-user rejoin: %v", err)
	}
	if len(resumed.Msg.Table.Players) != 2 || resumed.Msg.PlayerId != joined.Msg.PlayerId {
		t.Fatalf("same-user rejoin duplicated membership: %#v", resumed.Msg)
	}
	tableID := created.Msg.Table.Id
	if _, err := connectClient.LeaveTable(ctx, authenticated(&minimatchv1.LeaveTableRequest{
		TableId:  tableID,
		PlayerId: joined.Msg.PlayerId,
	}, "host-token")); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("spoofed leave code = %v, want permission denied", connect.CodeOf(err))
	}
	if _, err := grpcClient.LeaveTable(ctx, authenticated(&minimatchv1.LeaveTableRequest{
		TableId:  tableID,
		PlayerId: joined.Msg.PlayerId,
	}, "player-token")); err != nil {
		t.Fatal(err)
	}
	joined, err = grpcClient.JoinTable(ctx, authenticated(&minimatchv1.JoinTableRequest{
		JoinCode:    created.Msg.Table.JoinCode,
		DisplayName: "Liam",
		Avatar:      "owl",
	}, "player-token"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := repository.Update(ctx, tableID, func(table *game.Table) error {
		if err := table.SetGameCenterID(created.Msg.PlayerId, "game-center-host"); err != nil {
			return err
		}
		return table.SetGameCenterID(joined.Msg.PlayerId, "game-center-player")
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := connectClient.BeginRound(ctx, authenticated(&minimatchv1.BeginRoundRequest{
		TableId:      tableID,
		HostPlayerId: created.Msg.PlayerId,
	}, "host-token")); err != nil {
		t.Fatal(err)
	}
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
		Pick:        &minimatchv1.Pick{Value: 0},
		RoundNumber: 1,
	}, "host-token")); connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("zero pick code = %v, want invalid argument", connect.CodeOf(err))
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
	if got := beforeReveal.Msg.Table.Players; len(got) != 2 ||
		got[0].GetDisplayName() != "Maya" || got[0].GetAvatar() != "fox" ||
		got[1].GetDisplayName() != "Liam" || got[1].GetAvatar() != "owl" {
		t.Fatalf("profiles = %#v, want Firestore-ready names and avatars", got)
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
	revealed, err := connectClient.RevealRound(ctx, authenticated(&minimatchv1.RevealRoundRequest{
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
	for _, selection := range revealed.Msg.Table.LastResult.Selections {
		if selection.Wins == nil {
			t.Fatalf("selection %q omitted its table win count", selection.PlayerId)
		}
	}
	if revealed.Msg.Table.CurrentRound != nil ||
		revealed.Msg.Table.State != minimatchv1.TableState_TABLE_STATE_ACTIVE ||
		revealed.Msg.Table.WinsToFinish != 0 ||
		revealed.Msg.Table.WinnerPlayerId != nil ||
		revealed.Msg.Table.Players[0].Wins != 1 ||
		revealed.Msg.Table.Players[1].Wins != 0 {
		t.Fatal("reveal did not return the active lobby with table wins")
	}
	if repository.reveals != 1 {
		t.Fatalf("RevealRound repository calls = %d, want 1", repository.reveals)
	}

	if _, err := grpcClient.BeginRound(ctx, authenticated(&minimatchv1.BeginRoundRequest{
		TableId:      tableID,
		HostPlayerId: created.Msg.PlayerId,
	}, "host-token")); err != nil {
		t.Fatal(err)
	}
	for _, pick := range []struct {
		playerID string
		value    uint64
		token    string
	}{{created.Msg.PlayerId, 5, "host-token"}, {joined.Msg.PlayerId, 2, "player-token"}} {
		if _, err := connectClient.LockPick(ctx, authenticated(&minimatchv1.LockPickRequest{
			TableId:     tableID,
			PlayerId:    pick.playerID,
			Pick:        &minimatchv1.Pick{Value: pick.value},
			RoundNumber: 2,
		}, pick.token)); err != nil {
			t.Fatal(err)
		}
	}
	legacy, err := connectClient.StartRound(ctx, authenticated(&minimatchv1.StartRoundRequest{
		TableId:      tableID,
		HostPlayerId: created.Msg.PlayerId,
		RoundNumber:  2,
	}, "host-token"))
	if err != nil {
		t.Fatal(err)
	}
	if legacy.Msg.Table.CurrentRound != nil || legacy.Msg.Table.LastResult.GetRoundNumber() != 2 {
		t.Fatal("legacy StartRound did not reveal the active round")
	}
	guestPoll, err := grpcClient.GetTable(ctx, authenticated(
		&minimatchv1.GetTableRequest{TableId: tableID},
		"player-token",
	))
	if err != nil {
		t.Fatal(err)
	}
	if got := guestPoll.Msg.Table.LastResult.GetLocalPlayerLeaderboardScore(); got != 1 {
		t.Fatalf("guest winner leaderboard score = %d, want 1", got)
	}
	if guestPoll.Msg.Table.Players[0].Wins != 1 || guestPoll.Msg.Table.Players[1].Wins != 1 {
		t.Fatal("guest poll did not include both table win counts")
	}
	hostPoll, err := connectClient.GetTable(ctx, authenticated(
		&minimatchv1.GetTableRequest{TableId: tableID},
		"host-token",
	))
	if err != nil {
		t.Fatal(err)
	}
	if hostPoll.Msg.Table.LastResult.LocalPlayerLeaderboardScore != nil {
		t.Fatal("guest winner leaderboard score leaked to the host")
	}
	if repository.reveals != 2 {
		t.Fatalf("reveal aliases repository calls = %d, want 2", repository.reveals)
	}
}

func TestToProtoReturnsLeaderboardScoreOnlyToWinner(t *testing.T) {
	table, _ := game.NewTable("table", "Friday", "ABC-DEF", "maya", "Maya", "fox")
	table.LastResult = &game.Result{
		RoundNumber:         9,
		WinnerID:            "maya",
		WinnerTotalWins:     64,
		WinnerWinStreak:     4,
		WinnerBestWinStreak: 8,
	}
	table.WinnerLifetimeWins = 64

	result := toProto(table, "maya").GetLastResult()
	if result.GetWinnerTotalWins() != 0 || result.GetWinnerWinStreak() != 0 ||
		result.GetWinnerBestWinStreak() != 0 {
		t.Fatalf("exact winner stats leaked into the shared response: %#v", result)
	}
	if result.GetLocalPlayerLeaderboardScore() != 64 {
		t.Fatalf("winner leaderboard score = %d, want 64", result.GetLocalPlayerLeaderboardScore())
	}
	if toProto(table, "zoe").GetLastResult().LocalPlayerLeaderboardScore != nil {
		t.Fatal("winner leaderboard score leaked to another player")
	}
	wantAchievements := []string{
		"com.yazdanra.minimatch.achievement.twoWinStreak",
		"com.yazdanra.minimatch.achievement.fourWinStreak",
		"com.yazdanra.minimatch.achievement.sixteenRoundWins",
		"com.yazdanra.minimatch.achievement.thirtyTwoRoundWins",
		"com.yazdanra.minimatch.achievement.sixtyFourRoundWins",
	}
	if !slices.Equal(result.GetWinnerAchievementIds(), wantAchievements) {
		t.Fatalf("winner achievements = %v, want %v", result.GetWinnerAchievementIds(), wantAchievements)
	}
	if toProto(table, "maya").WinnerLifetimeWins != nil {
		t.Fatal("new round wins leaked into deprecated completed-match totals")
	}
}

func TestPollingExpiresStaleMemberAndAllowsRejoin(t *testing.T) {
	now := time.Date(2026, time.August, 3, 12, 0, 0, 0, time.UTC)
	service := New(game.NewMemoryRepository())
	service.now = func() time.Time { return now }
	path, handler := minimatchv1connect.NewMiniMatchServiceHandler(
		service,
		connect.WithInterceptors(authn.NewInterceptor(testVerifier{
			"host-token":   "maya",
			"active-token": "zoe",
			"stale-token":  "liam",
		})),
	)
	mux := http.NewServeMux()
	mux.Handle(path, handler)
	server := httptest.NewServer(mux)
	t.Cleanup(server.Close)
	client := minimatchv1connect.NewMiniMatchServiceClient(server.Client(), server.URL)
	ctx := context.Background()

	created, err := client.CreateTable(ctx, authenticated(&minimatchv1.CreateTableRequest{
		Name:            "Friday",
		HostDisplayName: "Maya",
	}, "host-token"))
	if err != nil {
		t.Fatal(err)
	}
	joinCode := created.Msg.Table.JoinCode
	for _, player := range []struct {
		token string
		name  string
	}{{"active-token", "Zoe"}, {"stale-token", "Liam"}} {
		if _, err := client.JoinTable(ctx, authenticated(&minimatchv1.JoinTableRequest{
			JoinCode: joinCode, DisplayName: player.name,
		}, player.token)); err != nil {
			t.Fatal(err)
		}
	}
	tableID := created.Msg.Table.Id
	if _, err := client.BeginRound(ctx, authenticated(&minimatchv1.BeginRoundRequest{
		TableId: tableID, HostPlayerId: "maya",
	}, "host-token")); err != nil {
		t.Fatal(err)
	}
	for _, pick := range []struct {
		token string
		id    string
		value uint64
	}{{"host-token", "maya", 2}, {"active-token", "zoe", 5}} {
		if _, err := client.LockPick(ctx, authenticated(&minimatchv1.LockPickRequest{
			TableId: tableID, PlayerId: pick.id,
			Pick: &minimatchv1.Pick{Value: pick.value}, RoundNumber: 1,
		}, pick.token)); err != nil {
			t.Fatal(err)
		}
	}

	now = now.Add(playerPresenceDuration/2 + time.Second)
	for _, token := range []string{"host-token", "active-token"} {
		if _, err := client.GetTable(ctx, authenticated(
			&minimatchv1.GetTableRequest{TableId: tableID}, token,
		)); err != nil {
			t.Fatal(err)
		}
	}
	now = now.Add(playerPresenceDuration / 2)
	ready, err := client.GetTable(ctx, authenticated(
		&minimatchv1.GetTableRequest{TableId: tableID}, "host-token",
	))
	if err != nil {
		t.Fatal(err)
	}
	if len(ready.Msg.Table.Players) != 2 ||
		ready.Msg.Table.CurrentRound.GetPhase() != minimatchv1.RoundPhase_ROUND_PHASE_READY_TO_REVEAL {
		t.Fatalf("stale member did not unblock reveal: %#v", ready.Msg.Table)
	}
	if _, err := client.RevealRound(ctx, authenticated(&minimatchv1.RevealRoundRequest{
		TableId: tableID, HostPlayerId: "maya", RoundNumber: 1,
	}, "host-token")); err != nil {
		t.Fatalf("reveal after eviction: %v", err)
	}
	if _, err := client.GetTable(ctx, authenticated(
		&minimatchv1.GetTableRequest{TableId: tableID}, "stale-token",
	)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("evicted member poll code = %v, want permission denied", connect.CodeOf(err))
	}
	rejoined, err := client.JoinTable(ctx, authenticated(&minimatchv1.JoinTableRequest{
		JoinCode: joinCode, DisplayName: "Liam",
	}, "stale-token"))
	if err != nil {
		t.Fatalf("evicted member rejoin: %v", err)
	}
	if len(rejoined.Msg.Table.Players) != 3 {
		t.Fatalf("rejoined players = %d, want 3", len(rejoined.Msg.Table.Players))
	}
}

func authenticated[T any](message *T, token string) *connect.Request[T] {
	request := connect.NewRequest(message)
	request.Header().Set("Authorization", "Bearer "+token)
	return request
}
