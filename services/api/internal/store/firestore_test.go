package store

import (
	"math"
	"reflect"
	"testing"

	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

func TestFirestoreDocumentsKeepPicksPrivateAndPreserveUint64(t *testing.T) {
	table, err := game.NewTable("table", "Friday", "ABC123", "maya", "Maya")
	if err != nil {
		t.Fatal(err)
	}
	if err := table.LockPick("maya", math.MaxUint64, 1); err != nil {
		t.Fatal(err)
	}
	table.Version = math.MaxUint64
	table.EventSequence = math.MaxUint64

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
	if decoded.Players[0].Pick != math.MaxUint64 || decoded.Version != math.MaxUint64 || decoded.EventSequence != math.MaxUint64 {
		t.Fatal("private document did not round-trip uint64 values")
	}
	public := publicDocument(table)
	if _, exposed := reflect.TypeOf(public.Players[0]).FieldByName("Pick"); exposed {
		t.Fatal("safe player document exposes a private pick")
	}
	if public.LastResult != nil {
		t.Fatal("safe document published a result before reveal")
	}

	if err := table.StartRound("maya", 1); err != nil {
		t.Fatal(err)
	}
	public = publicDocument(table)
	if got := public.LastResult.Selections[0].Pick; got != "18446744073709551615" {
		t.Fatalf("revealed pick = %q", got)
	}
}
