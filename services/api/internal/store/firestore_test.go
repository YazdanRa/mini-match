package store

import (
	"math"
	"reflect"
	"testing"
	"time"

	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

func TestFirestoreDocumentsKeepPicksPrivateAndPreserveUint64(t *testing.T) {
	table, err := game.NewTable("table", "Friday", "ABC123", "maya", "Maya", "fox")
	if err != nil {
		t.Fatal(err)
	}
	if err := table.Join("liam", "Liam", "owl"); err != nil {
		t.Fatal(err)
	}
	if err := table.BeginRound("maya"); err != nil {
		t.Fatal(err)
	}
	if err := table.LockPick("maya", math.MaxUint64, 1); err != nil {
		t.Fatal(err)
	}
	table.Version = math.MaxUint64
	table.EventSequence = math.MaxUint64
	table.WinnerLifetimeWins = math.MaxUint64
	table.Players[0].GameCenterID = "game-center-maya"
	table.Players[0].PresenceExpiresAt = time.Date(2026, time.August, 3, 12, 2, 0, 0, time.UTC)

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
		!decoded.Players[0].PresenceExpiresAt.Equal(table.Players[0].PresenceExpiresAt) ||
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
	if _, exposed := reflect.TypeOf(public.Players[0]).FieldByName("PresenceExpiresAt"); exposed {
		t.Fatal("safe player document exposes a private presence lease")
	}
	if public.LastResult != nil {
		t.Fatal("safe document published a result before reveal")
	}

	if err := table.LockPick("liam", 1, 1); err != nil {
		t.Fatal(err)
	}
	if err := table.RevealRound("maya", 1); err != nil {
		t.Fatal(err)
	}
	public = publicDocument(table)
	if public.CurrentRound != nil || public.State != "active" ||
		public.WinsToFinish != 0 || public.WinnerPlayerID != "" {
		t.Fatal("revealed round did not project the scoreless lobby state")
	}
	if got := public.LastResult.Selections[0].Pick; got != "18446744073709551615" {
		t.Fatalf("revealed pick = %q", got)
	}
	if got := public.ResultPlayerIDs; !reflect.DeepEqual(got, []string{"maya", "liam"}) {
		t.Fatalf("result player IDs = %#v", got)
	}
}

func TestLegacyFinishedDocumentReturnsToLobby(t *testing.T) {
	document := tableDocument{
		Name:         "Friday",
		JoinCode:     "ABC123",
		HostID:       "maya",
		CurrentRound: &roundDocument{Number: 5, Phase: "ready_to_reveal"},
		LastResult:   &resultDocument{RoundNumber: 5, WinnerID: "maya"},
		WinnerID:     "maya",
		Players: []playerDocument{
			{ID: "maya", Name: "Maya", Locked: true, Pick: "2"},
			{ID: "zoe", Name: "Zoe", Locked: true, Pick: "5"},
		},
		Version:       "10",
		EventSequence: "10",
	}
	table, err := decodeDocument("table", document)
	if err != nil {
		t.Fatal(err)
	}
	if table.CurrentRound != nil || table.Players[0].Locked || table.Players[0].Pick != 0 {
		t.Fatal("legacy finished table did not migrate to a clean lobby")
	}
	if err := table.BeginRound("maya"); err != nil {
		t.Fatalf("legacy table could not begin its next round: %v", err)
	}
	if table.CurrentRound.Number != 6 {
		t.Fatalf("legacy next round = %d, want 6", table.CurrentRound.Number)
	}
}
