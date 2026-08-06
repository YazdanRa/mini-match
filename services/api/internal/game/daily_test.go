package game

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"
)

func TestResolveDailyRound(t *testing.T) {
	tests := []struct {
		name    string
		entries []DailyEntry
		status  DailyRoundStatus
		pick    uint64
		winner  string
	}{
		{name: "empty", status: DailyRoundEmpty},
		{name: "insufficient", entries: []DailyEntry{{PlayerHash: "a", Pick: 1}}, status: DailyRoundInsufficient},
		{
			name: "lowest unique",
			entries: []DailyEntry{
				{PlayerHash: "d", Pick: math.MaxUint64},
				{PlayerHash: "b", Pick: 1},
				{PlayerHash: "c", Pick: 2},
				{PlayerHash: "a", Pick: 1},
			},
			status: DailyRoundWinner,
			pick:   2,
			winner: "c",
		},
		{
			name: "no unique",
			entries: []DailyEntry{
				{PlayerHash: "a", Pick: 1}, {PlayerHash: "b", Pick: 1},
				{PlayerHash: "c", Pick: 2}, {PlayerHash: "d", Pick: 2},
			},
			status: DailyRoundNoUnique,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result, err := ResolveDailyRound(test.entries)
			if err != nil {
				t.Fatal(err)
			}
			if result.Status != test.status || result.WinningPick != test.pick || result.WinnerHash != test.winner ||
				result.EntrantCount != uint64(len(test.entries)) {
				t.Fatalf("resolution = %#v", result)
			}
		})
	}
}

func TestMemoryDailyGlobalTableLifecycleAndPrivacy(t *testing.T) {
	ctx := context.Background()
	repository := NewMemoryRepository()
	now := time.Date(2026, time.August, 6, 23, 59, 0, 0, time.UTC)
	for _, player := range []struct {
		actor string
		gc    string
		pick  uint64
	}{{"maya", "gc-maya", 1}, {"zoe", "gc-zoe", 1}, {"liam", "gc-liam", 2}} {
		state, err := repository.LockDailyGlobalPick(ctx, player.actor, player.gc, "2026-08-06", player.pick, now)
		if err != nil {
			t.Fatal(err)
		}
		if state.Today.Pick != player.pick || state.Today.EntrantCount != 0 {
			t.Fatalf("open actor view = %#v", state.Today)
		}
	}
	afterClose := time.Date(2026, time.August, 7, 0, 0, 0, 0, time.UTC)
	winner, err := repository.GetDailyGlobalTable(ctx, "liam", "gc-liam", afterClose)
	if err != nil {
		t.Fatal(err)
	}
	if winner.Yesterday.Status != DailyRoundWinner || winner.Yesterday.WinningPick != 2 ||
		winner.Yesterday.EntrantCount != 3 || !winner.Yesterday.Won || winner.Yesterday.Pick != 2 || winner.TotalWins != 1 {
		t.Fatalf("winner state = %#v", winner)
	}
	other, err := repository.GetDailyGlobalTable(ctx, "maya", "gc-maya", afterClose)
	if err != nil {
		t.Fatal(err)
	}
	if other.Yesterday.Pick != 1 || other.Yesterday.Won || other.TotalWins != 0 {
		t.Fatalf("other actor state = %#v", other)
	}
	if len(repository.dailyRounds["2026-08-06"].Entries) != 3 || repository.dailyStats[dailyIdentityHash("player", "gc-liam")] != 1 {
		t.Fatal("finalization did not preserve private entries or credit exactly once")
	}
	if _, err := repository.GetDailyGlobalTable(ctx, "liam", "gc-liam", afterClose.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if repository.dailyStats[dailyIdentityHash("player", "gc-liam")] != 1 {
		t.Fatal("repeat read credited the winner twice")
	}
}

func TestMemoryDailyGlobalPickIsImmutableAndUniquePerIdentity(t *testing.T) {
	ctx := context.Background()
	repository := NewMemoryRepository()
	now := time.Date(2026, time.August, 6, 12, 0, 0, 0, time.UTC)
	if _, err := repository.LockDailyGlobalPick(ctx, "maya", "gc-maya", "2026-08-06", math.MaxUint64, now); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "maya", "gc-maya", "2026-08-06", math.MaxUint64, now); err != nil {
		t.Fatalf("exact retry = %v", err)
	}
	for _, test := range []struct {
		name  string
		actor string
		gc    string
		pick  uint64
	}{
		{"changed pick", "maya", "gc-maya", 1},
		{"changed Game Center identity", "maya", "gc-other", 1},
		{"changed Firebase account", "other", "gc-maya", math.MaxUint64},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := repository.LockDailyGlobalPick(ctx, test.actor, test.gc, "2026-08-06", test.pick, now); !errors.Is(err, ErrAlreadyLocked) {
				t.Fatalf("error = %v, want ErrAlreadyLocked", err)
			}
		})
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "zero", "gc-zero", "2026-08-06", 0, now); !errors.Is(err, ErrInvalid) {
		t.Fatalf("zero error = %v", err)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "late", "gc-late", "2026-08-05", 1, now); !errors.Is(err, ErrRoundMismatch) {
		t.Fatalf("stale date error = %v", err)
	}
}

func TestMemoryDeleteProfilePreservesDailyPickAndWins(t *testing.T) {
	ctx := context.Background()
	repository := NewMemoryRepository()
	now := time.Date(2026, time.August, 6, 12, 0, 0, 0, time.UTC)
	_, _ = repository.LockDailyGlobalPick(ctx, "maya", "gc-maya", "2026-08-06", 1, now)
	_, _ = repository.LockDailyGlobalPick(ctx, "zoe", "gc-zoe", "2026-08-06", 2, now)
	if err := repository.DeleteProfile(ctx, "maya"); err != nil {
		t.Fatal(err)
	}
	if linkedPlayer, claimed := repository.dailyRounds["2026-08-06"].Claims[dailyIdentityHash("account", "maya")]; !claimed || linkedPlayer != "" {
		t.Fatal("deleted profile claim was not anonymized into a deny-only tombstone")
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "maya", "gc-new", "2026-08-06", 3, now); !errors.Is(err, ErrAlreadyLocked) {
		t.Fatalf("deleted account locked a second pick: %v", err)
	}
	state, err := repository.GetDailyGlobalTable(ctx, "maya", "gc-maya", now.Add(12*time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if state.Yesterday.Pick != 1 || !state.Yesterday.Won || state.TotalWins != 1 {
		t.Fatalf("deleted profile Daily state = %#v", state)
	}
}
