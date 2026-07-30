package store

import (
	"math"
	"reflect"
	"testing"

	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

func TestFirestoreDocumentsKeepPicksPrivateAndPreserveUint64(t *testing.T) {
	table, err := game.NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	if err != nil {
		t.Fatal(err)
	}
	if err := table.LockPick("maya", math.MaxUint64, 1); err != nil {
		t.Fatal(err)
	}
	if err := table.Join("liam", "Liam", "owl"); err != nil {
		t.Fatal(err)
	}
	table.Version = math.MaxUint64
	table.EventSequence = math.MaxUint64
	table.WinnerLifetimeWins = math.MaxUint64
	table.Players[0].GameCenterID = "game-center-maya"

	private := privateDocument(table)
	if got := private.Players[0].Pick; got != "18446744073709551615" {
		t.Fatalf("private pick = %q", got)
	}
	if private.Version != "18446744073709551615" || private.EventSequence != "18446744073709551615" {
		t.Fatal("private document truncated uint64 counters")
	}
	decoded, err := decodeDocument(table.ID, private)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.Players[0].Pick != math.MaxUint64 ||
		decoded.Version != math.MaxUint64 ||
		decoded.EventSequence != math.MaxUint64 ||
		decoded.WinnerLifetimeWins != math.MaxUint64 {
		t.Fatal("private document did not round-trip uint64 values")
	}
	if decoded.Players[0].Name != "Maya" || decoded.Players[0].Avatar != "fox" ||
		decoded.Players[0].GameCenterID != "game-center-maya" ||
		decoded.Players[1].Name != "Liam" || decoded.Players[1].Avatar != "owl" {
		t.Fatal("player profiles did not round-trip through the private Firestore document")
	}
	public := publicDocument(table)
	if public.WinnerLifetimeWins != "18446744073709551615" {
		t.Fatal("public document truncated winner lifetime wins")
	}
	if private.Players[0].Name != "Maya" || private.Players[0].Avatar != "fox" ||
		private.Players[1].Name != "Liam" || private.Players[1].Avatar != "owl" ||
		public.Players[0].Name != "Maya" || public.Players[0].Avatar != "fox" ||
		public.Players[1].Name != "Liam" || public.Players[1].Avatar != "owl" {
		t.Fatal("player profile was not preserved in Firestore projections")
	}
	if _, exposed := reflect.TypeOf(public.Players[0]).FieldByName("Pick"); exposed {
		t.Fatal("safe player document exposes a private pick")
	}
	if public.LastResult != nil {
		t.Fatal("safe document published a result before reveal")
	}

	if err := table.LockPick("liam", 1, 1); err != nil {
		t.Fatal(err)
	}
	if err := table.StartRound("maya", 1); err != nil {
		t.Fatal(err)
	}
	public = publicDocument(table)
	if got := public.LastResult.Selections[0].Pick; got != "18446744073709551615" {
		t.Fatalf("revealed pick = %q", got)
	}
}
