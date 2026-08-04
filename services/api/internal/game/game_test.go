package game

import (
	"context"
	"errors"
	"math"
	"strings"
	"testing"
	"time"
)

func TestTableRules(t *testing.T) {
	table, err := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	if err != nil {
		t.Fatal(err)
	}
	if table.Players[0].Name != "Maya" || table.Players[0].Avatar != "fox" {
		t.Fatal("host profile was not normalized")
	}
	for id, name := range map[string]string{"zoe": "Zoe", "liam": "Liam"} {
		if err := table.Join(id, name, "owl"); err != nil {
			t.Fatal(err)
		}
	}
	if table.CurrentRound != nil {
		t.Fatal("new table did not start in the lobby")
	}
	if !errors.Is(table.BeginRound("zoe"), ErrForbidden) {
		t.Fatal("non-host started the round")
	}
	if err := table.BeginRound("maya"); err != nil {
		t.Fatal(err)
	}
	if !errors.Is(table.BeginRound("maya"), ErrRoundActive) {
		t.Fatal("host started a second round while one was active")
	}
	if err := table.LockPick("maya", 2, 1); err != nil {
		t.Fatal(err)
	}
	if err := table.LockPick("zoe", 2, 1); err != nil {
		t.Fatal(err)
	}
	if err := table.LockPick("liam", 5, 1); err != nil {
		t.Fatal(err)
	}
	if table.CurrentRound.Phase != RoundReady {
		t.Fatal("round did not become ready after every player locked")
	}
	if !errors.Is(table.RevealRound("zoe", 1), ErrForbidden) {
		t.Fatal("non-host revealed the round")
	}
	if err := table.RevealRound("maya", 1); err != nil {
		t.Fatal(err)
	}
	if got := table.LastResult.WinnerID; got != "liam" {
		t.Fatalf("winner = %q, want liam", got)
	}
	if table.CurrentRound != nil {
		t.Fatal("revealed round did not return to the lobby")
	}
	for _, player := range table.Players {
		if player.Locked {
			t.Fatalf("%s remained locked after reveal", player.ID)
		}
	}
	version := table.Version
	if err := table.LockPick("maya", 0, 1); !errors.Is(err, ErrNotReady) {
		t.Fatalf("lobby lock error = %v, want ErrNotReady", err)
	}
	if table.player("maya").Locked || table.Version != version {
		t.Fatal("stale lock changed table state")
	}

	for round := 2; round <= 6; round++ {
		if err := table.BeginRound("maya"); err != nil {
			t.Fatalf("round %d start: %v", round, err)
		}
		for _, id := range []string{"maya", "zoe", "liam"} {
			pick := uint64(1)
			if id == "liam" {
				pick = 0
			}
			if err := table.LockPick(id, pick, uint32(round)); err != nil {
				t.Fatalf("round %d lock: %v", round, err)
			}
		}
		if err := table.RevealRound("maya", uint32(round)); err != nil {
			t.Fatalf("round %d reveal: %v", round, err)
		}
	}
	if got := table.LastResult.RoundNumber; got != 6 {
		t.Fatalf("last result round = %d, want 6", got)
	}
	if err := table.BeginRound("maya"); err != nil {
		t.Fatalf("table did not allow an independent seventh round: %v", err)
	}
}

func TestSoloPlayerCannotBeginRound(t *testing.T) {
	table, err := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	if err != nil {
		t.Fatal(err)
	}
	if !errors.Is(table.BeginRound("maya"), ErrNotReady) {
		t.Fatal("solo player started the round")
	}
}

func TestRevealedResultKeepsPlayerNamesAfterLeave(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "")
	_ = table.Join("liam", "Liam", "")
	_ = table.BeginRound("maya")
	_ = table.LockPick("maya", 2, 1)
	_ = table.LockPick("liam", 5, 1)
	_ = table.RevealRound("maya", 1)
	_ = table.Leave("liam")

	if got := table.LastResult.Selections[1].DisplayName; got != "Liam" {
		t.Fatalf("departed player name = %q, want Liam", got)
	}
}

func TestRoundNumberCannotWrap(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "")
	_ = table.Join("zoe", "Zoe", "")
	table.LastResult = &Result{RoundNumber: math.MaxUint32}
	if err := table.BeginRound("maya"); !errors.Is(err, ErrRoundExhausted) {
		t.Fatalf("wrapped start error = %v, want ErrRoundExhausted", err)
	}
}

func TestProfileInputBounds(t *testing.T) {
	if _, err := NewTable(
		"table",
		strings.Repeat("t", maxTableNameLength),
		"ABC123",
		"maya",
		strings.Repeat("n", maxPlayerNameLength),
		"",
	); err != nil {
		t.Fatalf("boundary profile rejected: %v", err)
	}
	if _, err := NewTable(
		"table",
		strings.Repeat("t", maxTableNameLength+1),
		"ABC123",
		"maya",
		"Maya",
		"fox",
	); !errors.Is(err, ErrInvalid) {
		t.Fatalf("oversized table name error = %v, want ErrInvalid", err)
	}
	if _, err := NewTable(
		"table",
		"Friday",
		"ABC123",
		"maya",
		strings.Repeat("n", maxPlayerNameLength+1),
		"fox",
	); !errors.Is(err, ErrInvalid) {
		t.Fatalf("oversized display name error = %v, want ErrInvalid", err)
	}
	if _, err := NewTable("table", "Friday", "ABC123", "maya", "Maya", "unknown"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("unknown avatar error = %v, want ErrInvalid", err)
	}
}

func TestProfileInputBoundsCountUnicodeCharacters(t *testing.T) {
	if _, err := NewTable(
		"table",
		strings.Repeat("桌", maxTableNameLength),
		"ABC123",
		"maya",
		strings.Repeat("名", maxPlayerNameLength),
		"",
	); err != nil {
		t.Fatalf("Unicode boundary profile rejected: %v", err)
	}
	if _, err := NewTable(
		"table",
		strings.Repeat("桌", maxTableNameLength+1),
		"ABC123",
		"maya",
		"Maya",
		"",
	); !errors.Is(err, ErrInvalid) {
		t.Fatalf("oversized Unicode table name error = %v, want ErrInvalid", err)
	}
	if _, err := NewTable(
		"table",
		"Friday",
		"ABC123",
		"maya",
		strings.Repeat("名", maxPlayerNameLength+1),
		"",
	); !errors.Is(err, ErrInvalid) {
		t.Fatalf("oversized Unicode display name error = %v, want ErrInvalid", err)
	}
}

func TestNoUniquePickHasNoWinner(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "")
	_ = table.Join("zoe", "Zoe", "")
	_ = table.Join("liam", "Liam", "")
	_ = table.Join("noah", "Noah", "")
	_ = table.BeginRound("maya")
	for id, pick := range map[string]uint64{"maya": 2, "zoe": 2, "liam": 5, "noah": 5} {
		if err := table.LockPick(id, pick, 1); err != nil {
			t.Fatal(err)
		}
	}
	if err := table.RevealRound("maya", 1); err != nil {
		t.Fatal(err)
	}
	if table.LastResult.WinnerID != "" {
		t.Fatalf("winner = %q, want none", table.LastResult.WinnerID)
	}
}

func TestLeaveRemovesPlayerAndPromotesHost(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")
	_ = table.Join("liam", "Liam", "frog")
	_ = table.BeginRound("maya")
	_ = table.LockPick("zoe", 2, 1)
	_ = table.LockPick("liam", 5, 1)

	if err := table.Leave("maya"); err != nil {
		t.Fatal(err)
	}
	if table.HostID != "zoe" || len(table.Players) != 2 || table.CurrentRound.Phase != RoundReady {
		t.Fatalf("leave result = host %q, %d players, phase %v", table.HostID, len(table.Players), table.CurrentRound.Phase)
	}
	if err := table.RevealRound("zoe", 1); err != nil {
		t.Fatalf("promoted host could not reveal: %v", err)
	}

	empty, _ := NewTable("empty", "Friday", "EMPTY", "maya", "Maya", "fox")
	if err := empty.Leave("maya"); err != nil {
		t.Fatal(err)
	}
	if err := empty.Join("noah", "Noah", "cat"); err != nil {
		t.Fatal(err)
	}
	if empty.HostID != "noah" || empty.CurrentRound != nil {
		t.Fatal("first player to rejoin an empty table did not become host")
	}
}

func TestSamePlayerRejoinResumesWithoutResettingTheRound(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")
	_ = table.BeginRound("maya")
	_ = table.LockPick("zoe", 5, 1)

	if err := table.Join("zoe", "Zoë", "frog"); err != nil {
		t.Fatal(err)
	}
	if len(table.Players) != 2 {
		t.Fatalf("players = %d, want 2", len(table.Players))
	}
	player := table.player("zoe")
	if player.Name != "Zoë" || player.Avatar != "frog" || !player.Locked || player.Pick != 5 {
		t.Fatalf("resumed player = %#v", player)
	}
}

func TestGameCenterIdentityCannotBindMultiplePlayers(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")

	if err := table.SetGameCenterID("maya", "game-center-player"); err != nil {
		t.Fatal(err)
	}
	if err := table.SetGameCenterID("maya", "game-center-player"); err != nil {
		t.Fatalf("same-player reconnect error = %v, want nil", err)
	}
	if err := table.SetGameCenterID("zoe", "game-center-player"); !errors.Is(err, ErrAlreadyExists) {
		t.Fatalf("duplicate identity error = %v, want ErrAlreadyExists", err)
	}
	if err := table.SetGameCenterID("zoe", ""); err != nil {
		t.Fatalf("anonymous player identity error = %v, want nil", err)
	}
	if table.player("zoe").GameCenterID != "" {
		t.Fatalf("rejected player identity = %q, want empty", table.player("zoe").GameCenterID)
	}
}

func TestPresenceExpiryUnblocksReveal(t *testing.T) {
	now := time.Date(2026, time.August, 3, 12, 0, 0, 0, time.UTC)
	duration := 2 * time.Minute
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")
	_ = table.Join("liam", "Liam", "frog")
	_ = table.RefreshPresence("maya", now, duration)
	_ = table.RefreshPresence("zoe", now, duration)
	_ = table.RefreshPresence("liam", now, duration)
	_ = table.BeginRound("maya")
	_ = table.LockPick("maya", 2, 1)
	_ = table.LockPick("zoe", 5, 1)

	later := now.Add(duration + time.Second)
	table.player("maya").PresenceExpiresAt = later.Add(duration)
	table.player("zoe").PresenceExpiresAt = later.Add(duration)
	if err := table.RefreshPresence("maya", later, duration); err != nil {
		t.Fatal(err)
	}
	if table.HasPlayer("liam") || len(table.Players) != 2 || table.CurrentRound.Phase != RoundReady {
		t.Fatalf("expiry result = players %#v, phase %v", table.Players, table.CurrentRound.Phase)
	}
	if err := table.RevealRound("maya", 1); err != nil {
		t.Fatalf("remaining players could not reveal: %v", err)
	}
}

func TestPresenceExpiryPromotesHostAndCancelsUndersizedRound(t *testing.T) {
	now := time.Date(2026, time.August, 3, 12, 0, 0, 0, time.UTC)
	duration := 2 * time.Minute
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")
	_ = table.RefreshPresence("maya", now, duration)
	_ = table.RefreshPresence("zoe", now, duration)
	_ = table.BeginRound("maya")
	_ = table.LockPick("zoe", 5, 1)

	later := now.Add(duration + time.Second)
	table.player("zoe").PresenceExpiresAt = later.Add(duration)
	if err := table.RefreshPresence("zoe", later, duration); err != nil {
		t.Fatal(err)
	}
	if table.HostID != "zoe" || table.CurrentRound != nil || table.player("zoe").Locked ||
		table.player("zoe").Pick != 0 {
		t.Fatalf("undersized round was not reconciled: %#v", table)
	}
}

func TestPresenceRefreshBackfillsLegacyPlayersForOneLease(t *testing.T) {
	now := time.Date(2026, time.August, 3, 12, 0, 0, 0, time.UTC)
	duration := 2 * time.Minute
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")

	if !table.PresenceUpdateNeeded("maya", now, duration) {
		t.Fatal("legacy table did not request presence backfill")
	}
	if err := table.RefreshPresence("maya", now, duration); err != nil {
		t.Fatal(err)
	}
	for _, player := range table.Players {
		if got := player.PresenceExpiresAt; !got.Equal(now.Add(duration)) {
			t.Fatalf("%s expiry = %v", player.ID, got)
		}
	}
}

func TestMemoryRepositoryUpdateIsAtomic(t *testing.T) {
	ctx := context.Background()
	repository := NewMemoryRepository()
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "")
	if err := repository.Create(ctx, table); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.Update(ctx, table.ID, func(next *Table) error {
		next.Name = "changed"
		next.CurrentRound = &Round{Number: 99, Phase: RoundReady}
		return ErrInvalid
	}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("update error = %v, want ErrInvalid", err)
	}
	stored, err := repository.Get(ctx, table.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.Name != "Friday" || stored.CurrentRound != nil {
		t.Fatal("failed update changed stored table")
	}
}

func TestDeletePlayerProfileRemovesPlayerAndAnonymizesLastResult(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ACTIVE", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")
	table.LastResult = &Result{
		WinnerID:   "maya",
		Selections: []Selection{{PlayerID: "maya", DisplayName: "Maya", Pick: 2}},
	}
	if err := table.DeletePlayerProfile("maya", "deleted:table"); err != nil {
		t.Fatal(err)
	}
	if table.HasPlayer("maya") {
		t.Fatal("profile was not removed")
	}
	if table.LastResult.WinnerID != "deleted:table" ||
		table.LastResult.Selections[0].PlayerID != "deleted:table" ||
		table.LastResult.Selections[0].DisplayName != "" {
		t.Fatal("last result kept the deleted player ID")
	}
}

func TestDeletePlayerProfileAnonymizesResultAfterLeave(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ACTIVE", "maya", "Maya", "fox")
	_ = table.Join("zoe", "Zoe", "owl")
	table.LastResult = &Result{
		WinnerID:   "maya",
		Selections: []Selection{{PlayerID: "maya", DisplayName: "Maya", Pick: 2}},
	}
	_ = table.Leave("maya")

	if err := table.DeletePlayerProfile("maya", "deleted:table"); err != nil {
		t.Fatal(err)
	}
	if table.LastResult.WinnerID != "deleted:table" ||
		table.LastResult.Selections[0].PlayerID != "deleted:table" ||
		table.LastResult.Selections[0].DisplayName != "" {
		t.Fatal("departed player remained identifiable in the last result")
	}
}
