package store

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"slices"
	"sort"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

func TestDailyEntryDocumentsPreserveAndOrderUint64Picks(t *testing.T) {
	picks := []uint64{math.MaxUint64, 10, 2, 1, math.MaxInt64 + 1}
	documents := make([]dailyEntryDocument, 0, len(picks))
	for _, pick := range picks {
		document := newDailyEntryDocument("account-hash", pick)
		entry, err := decodeDailyEntryDocument("player-hash", document)
		if err != nil {
			t.Fatal(err)
		}
		if entry.Pick != pick || document.Pick == "" || len(document.PickKey) != 20 {
			t.Fatalf("pick %d encoded as %#v and decoded as %#v", pick, document, entry)
		}
		documents = append(documents, document)
	}
	sort.Slice(documents, func(i, j int) bool { return documents[i].PickKey < documents[j].PickKey })
	got := make([]uint64, 0, len(documents))
	for _, document := range documents {
		entry, _ := decodeDailyEntryDocument("player-hash", document)
		got = append(got, entry.Pick)
	}
	if want := []uint64{1, 2, 10, math.MaxInt64 + 1, math.MaxUint64}; !slices.Equal(got, want) {
		t.Fatalf("ordered picks = %v, want %v", got, want)
	}
}

func TestDailyFirestoreDocumentsArePrivateAndTTLStartsAfterFinalization(t *testing.T) {
	closesAt := time.Date(2026, time.August, 7, 0, 0, 0, 0, time.UTC)
	round := newDailyRoundDocument(closesAt)
	entry := newDailyEntryDocument(dailyAccountDocumentID("firebase-uid"), math.MaxUint64)
	claim := dailyClaimDocument{
		AccountHash: dailyAccountDocumentID("firebase-uid"),
		PlayerHash:  dailyPlayerDocumentID("game-center-id"),
		Pick:        entry.Pick,
	}
	if round.Status != string(game.DailyRoundOpen) || round.CleanupScheduled || entry.ExpiresAt != nil || claim.ExpiresAt != nil {
		t.Fatalf("new Daily documents = round %#v, entry %#v, claim %#v", round, entry, claim)
	}
	if entry.AccountHash == "firebase-uid" || claim.PlayerHash == "game-center-id" {
		t.Fatal("Daily persistence retained a raw identity")
	}
	if entry.AccountHash == statsDocumentID("firebase-uid") ||
		dailyAccountDocumentID("same") == dailyPlayerDocumentID("same") {
		t.Fatal("Daily identity hashes are not domain-separated")
	}
}

func TestDecodeDailyEntryRejectsZeroAndMalformedSortKeys(t *testing.T) {
	for _, document := range []dailyEntryDocument{
		{Pick: "0", PickKey: "00000000000000000000"},
		{Pick: "1", PickKey: "1"},
		{Pick: "18446744073709551616", PickKey: "18446744073709551616"},
	} {
		if _, err := decodeDailyEntryDocument("player", document); err == nil {
			t.Fatalf("decoded invalid Daily entry %#v", document)
		}
	}
}

func TestFirestoreDailyRoundFinalizesExactlyOnceAndSchedulesTTL(t *testing.T) {
	repository, closeClient := newDailyFirestoreTestRepository(t)
	defer closeClient()
	ctx := context.Background()
	now := time.Date(2026, time.August, 6, 23, 59, 0, 0, time.UTC)
	if _, err := repository.LockDailyGlobalPick(ctx, "maya", "gc-maya", "2026-08-06", math.MaxUint64, now); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "zoe", "gc-zoe", "2026-08-06", 1, now); err != nil {
		t.Fatal(err)
	}
	afterClose := now.Add(time.Minute)
	var wait sync.WaitGroup
	errorsSeen := make(chan error, 8)
	for range 8 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			state, err := repository.GetDailyGlobalTable(ctx, "zoe", "gc-zoe", afterClose)
			if err == nil && state.Yesterday.Status != game.DailyRoundCalculating &&
				(state.TotalWins != 1 || !state.Yesterday.Won || state.Yesterday.WinningPick != 1) {
				err = fmt.Errorf("unexpected settled state %#v", state)
			}
			if err != nil {
				errorsSeen <- err
			}
		}()
	}
	wait.Wait()
	close(errorsSeen)
	for err := range errorsSeen {
		t.Error(err)
	}
	state, err := repository.GetDailyGlobalTable(ctx, "zoe", "gc-zoe", afterClose)
	if err != nil {
		t.Fatal(err)
	}
	if state.TotalWins != 1 || !state.Yesterday.Won || state.Yesterday.WinningPick != 1 {
		t.Fatalf("final state = %#v", state)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "zoe", "gc-zoe", "2026-08-06", 1, afterClose); err != nil {
		t.Fatalf("exact post-cutoff retry = %v", err)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "zoe", "gc-zoe", "2026-08-06", 2, afterClose); !errors.Is(err, game.ErrAlreadyLocked) {
		t.Fatalf("changed post-cutoff retry = %v, want ErrAlreadyLocked", err)
	}
	round := repository.client.Collection(dailyRounds).Doc("2026-08-06")
	var summary dailyRoundDocument
	if snapshot, err := round.Get(ctx); err != nil {
		t.Fatal(err)
	} else if err := snapshot.DataTo(&summary); err != nil {
		t.Fatal(err)
	}
	if summary.Status != string(game.DailyRoundWinner) || summary.WinningPick != "1" ||
		summary.EntrantCount != "2" || !summary.CleanupScheduled {
		t.Fatalf("summary = %#v", summary)
	}
	for _, reference := range []*firestore.DocumentRef{
		round.Collection(dailyEntries).Doc(dailyPlayerDocumentID("gc-zoe")),
		repository.dailyClaimRef(dailyAccountDocumentID("zoe"), "2026-08-06"),
	} {
		var document struct {
			ExpiresAt time.Time `firestore:"expires_at"`
		}
		if snapshot, err := reference.Get(ctx); err != nil {
			t.Fatal(err)
		} else if err := snapshot.DataTo(&document); err != nil {
			t.Fatal(err)
		}
		if want := summary.FinalizedAt.Add(dailyRetention); !document.ExpiresAt.Equal(want) {
			t.Fatalf("expires_at = %v, want %v", document.ExpiresAt, want)
		}
	}
}

func TestFirestoreDeleteProfileAnonymizesDailyPickWithoutAllowingAnother(t *testing.T) {
	repository, closeClient := newDailyFirestoreTestRepository(t)
	defer closeClient()
	ctx := context.Background()
	now := time.Date(2026, time.August, 6, 12, 0, 0, 0, time.UTC)
	if _, err := repository.LockDailyGlobalPick(ctx, "maya", "gc-maya", "2026-08-06", 1, now); err != nil {
		t.Fatal(err)
	}
	if err := repository.DeleteProfile(ctx, "maya"); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "maya", "gc-new", "2026-08-06", 2, now); !errors.Is(err, game.ErrAlreadyLocked) {
		t.Fatalf("second pick after deletion = %v, want ErrAlreadyLocked", err)
	}
	if _, err := repository.LockDailyGlobalPick(ctx, "zoe", "gc-zoe", "2026-08-06", 2, now); err != nil {
		t.Fatal(err)
	}
	round := repository.client.Collection(dailyRounds).Doc("2026-08-06")
	var claim dailyClaimDocument
	if snapshot, err := repository.dailyClaimRef(dailyAccountDocumentID("maya"), "2026-08-06").Get(ctx); err != nil {
		t.Fatal(err)
	} else if err := snapshot.DataTo(&claim); err != nil {
		t.Fatal(err)
	}
	var entry dailyEntryDocument
	if snapshot, err := round.Collection(dailyEntries).Doc(dailyPlayerDocumentID("gc-maya")).Get(ctx); err != nil {
		t.Fatal(err)
	} else if err := snapshot.DataTo(&entry); err != nil {
		t.Fatal(err)
	}
	if claim.AccountHash != "" || claim.PlayerHash != "" || claim.Pick != "" || claim.ExpiresAt == nil ||
		entry.AccountHash != "" || entry.Pick != "1" {
		t.Fatalf("claim %#v, entry %#v", claim, entry)
	}
	state, err := repository.GetDailyGlobalTable(ctx, "maya", "gc-maya", time.Date(2026, time.August, 7, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	if !state.Yesterday.Won || state.Yesterday.Pick != 1 || state.TotalWins != 1 {
		t.Fatalf("deleted winner state = %#v", state)
	}
}

func TestFirestoreDailyCalculationLeaseShowsCalculatingAndRecovers(t *testing.T) {
	repository, closeClient := newDailyFirestoreTestRepository(t)
	defer closeClient()
	ctx := context.Background()
	round := repository.client.Collection(dailyRounds).Doc("2026-08-06")
	closesAt := time.Date(2026, time.August, 7, 0, 0, 0, 0, time.UTC)
	if _, err := round.Set(ctx, dailyRoundDocument{
		ClosesAt:         closesAt,
		Status:           string(game.DailyRoundCalculating),
		CleanupScheduled: false,
		CalculationToken: "abandoned-worker",
		CalculationLease: closesAt.Add(2 * time.Minute),
	}); err != nil {
		t.Fatal(err)
	}
	for _, player := range []struct {
		actor string
		gc    string
		pick  uint64
	}{{"maya", "gc-maya", 1}, {"zoe", "gc-zoe", 2}} {
		if _, err := round.Collection(dailyEntries).Doc(dailyPlayerDocumentID(player.gc)).Set(
			ctx,
			newDailyEntryDocument(dailyAccountDocumentID(player.actor), player.pick),
		); err != nil {
			t.Fatal(err)
		}
	}
	state, err := repository.GetDailyGlobalTable(ctx, "maya", "gc-maya", closesAt.Add(time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if state.Today.Status != game.DailyRoundOpen || state.Yesterday.Status != game.DailyRoundCalculating {
		t.Fatalf("leased state = %#v", state)
	}
	state, err = repository.GetDailyGlobalTable(ctx, "maya", "gc-maya", closesAt.Add(3*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if state.Yesterday.Status != game.DailyRoundWinner || !state.Yesterday.Won || state.TotalWins != 1 {
		t.Fatalf("recovered state = %#v", state)
	}
}

func newDailyFirestoreTestRepository(t *testing.T) (*FirestoreRepository, func()) {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		t.Skip("FIRESTORE_EMULATOR_HOST is not set")
	}
	client, err := firestore.NewClient(context.Background(), fmt.Sprintf("mini-match-daily-%d", time.Now().UnixNano()))
	if err != nil {
		t.Fatal(err)
	}
	return NewFirestoreRepository(client), func() {
		if err := client.Close(); err != nil {
			t.Error(err)
		}
	}
}
