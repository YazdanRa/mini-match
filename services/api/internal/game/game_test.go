package game

import (
	"context"
	"errors"
	"strings"
	"testing"
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
	if err := table.LockPick("maya", 2, 1); err != nil {
		t.Fatal(err)
	}
	if !errors.Is(table.StartRound("zoe", 1), ErrForbidden) {
		t.Fatal("non-host started the round")
	}
	if !errors.Is(table.StartRound("maya", 1), ErrNotReady) {
		t.Fatal("round started before every player locked")
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
	if err := table.StartRound("maya", 1); err != nil {
		t.Fatal(err)
	}
	if got := table.LastResult.WinnerID; got != "liam" {
		t.Fatalf("winner = %q, want liam", got)
	}
	if got := table.player("liam").Score; got != 1 {
		t.Fatalf("score = %d, want 1", got)
	}
	if table.CurrentRound.Number != 2 {
		t.Fatalf("current round = %d, want 2", table.CurrentRound.Number)
	}
	for _, player := range table.Players {
		if player.Locked {
			t.Fatalf("%s remained locked after reveal", player.ID)
		}
	}
	version := table.Version
	if err := table.LockPick("maya", 0, 1); !errors.Is(err, ErrRoundMismatch) {
		t.Fatalf("stale lock error = %v, want ErrRoundMismatch", err)
	}
	if table.player("maya").Locked || table.Version != version {
		t.Fatal("stale lock changed table state")
	}

	for round := 2; round <= WinningScore; round++ {
		for _, id := range []string{"maya", "zoe", "liam"} {
			pick := uint64(1)
			if id == "liam" {
				pick = 0
			}
			if err := table.LockPick(id, pick, uint32(round)); err != nil {
				t.Fatalf("round %d lock: %v", round, err)
			}
		}
		if err := table.StartRound("maya", uint32(round)); err != nil {
			t.Fatalf("round %d reveal: %v", round, err)
		}
	}
	if table.WinnerID != "liam" {
		t.Fatalf("table winner = %q, want liam", table.WinnerID)
	}
	if got := table.LastResult.RoundNumber; got != WinningScore {
		t.Fatalf("last result round = %d, want %d", got, WinningScore)
	}
	if !errors.Is(table.LockPick("maya", 0, WinningScore+1), ErrFinished) {
		t.Fatal("finished table accepted another pick")
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

func TestNoUniquePickHasNoWinner(t *testing.T) {
	table, _ := NewTable("table", "Friday", "ABC123", "maya", "Maya", "")
	_ = table.Join("zoe", "Zoe", "")
	_ = table.Join("liam", "Liam", "")
	_ = table.Join("noah", "Noah", "")
	for id, pick := range map[string]uint64{"maya": 2, "zoe": 2, "liam": 5, "noah": 5} {
		if err := table.LockPick(id, pick, 1); err != nil {
			t.Fatal(err)
		}
	}
	if err := table.StartRound("maya", 1); err != nil {
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
	_ = table.LockPick("zoe", 2, 1)
	_ = table.LockPick("liam", 5, 1)

	if err := table.Leave("maya"); err != nil {
		t.Fatal(err)
	}
	if table.HostID != "zoe" || len(table.Players) != 2 || table.CurrentRound.Phase != RoundReady {
		t.Fatalf("leave result = host %q, %d players, phase %v", table.HostID, len(table.Players), table.CurrentRound.Phase)
	}
	if err := table.StartRound("zoe", 1); err != nil {
		t.Fatalf("promoted host could not reveal: %v", err)
	}

	empty, _ := NewTable("empty", "Friday", "EMPTY", "maya", "Maya", "fox")
	if err := empty.Leave("maya"); err != nil {
		t.Fatal(err)
	}
	if err := empty.Join("noah", "Noah", "cat"); err != nil {
		t.Fatal(err)
	}
	if empty.HostID != "noah" || empty.CurrentRound.Number != 1 {
		t.Fatal("first player to rejoin an empty table did not become host")
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
		return ErrInvalid
	}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("update error = %v, want ErrInvalid", err)
	}
	stored, err := repository.Get(ctx, table.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.Name != "Friday" {
		t.Fatalf("failed update changed stored table to %q", stored.Name)
	}
}
