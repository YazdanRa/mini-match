package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	dailyRounds      = "daily_rounds"
	dailyEntries     = "daily_entries"
	dailyClaims      = "daily_claims"
	dailyClaimRounds = "daily_round_claims"
	dailyPlayerStats = "daily_player_stats"
	dailyRetention   = 7 * 24 * time.Hour
	dailyCalcLease   = 2 * time.Minute
)

type dailyRoundDocument struct {
	ClosesAt         time.Time `firestore:"closes_at"`
	Status           string    `firestore:"status"`
	EntrantCount     string    `firestore:"entrant_count,omitempty"`
	WinningPick      string    `firestore:"winning_pick,omitempty"`
	FinalizedAt      time.Time `firestore:"finalized_at,omitempty"`
	CleanupScheduled bool      `firestore:"cleanup_scheduled"`
	CalculationToken string    `firestore:"calculation_token,omitempty"`
	CalculationLease time.Time `firestore:"calculation_lease_until,omitempty"`
}

type dailyEntryDocument struct {
	AccountHash string     `firestore:"account_hash,omitempty"`
	Pick        string     `firestore:"pick"`
	PickKey     string     `firestore:"pick_key"`
	ExpiresAt   *time.Time `firestore:"expires_at,omitempty"`
}

type dailyClaimDocument struct {
	AccountHash string     `firestore:"account_hash,omitempty"`
	PlayerHash  string     `firestore:"player_hash,omitempty"`
	Pick        string     `firestore:"pick"`
	ExpiresAt   *time.Time `firestore:"expires_at,omitempty"`
}

type dailyPlayerStatsDocument struct {
	TotalWins string `firestore:"total_wins,omitempty"`
}

func (r *FirestoreRepository) GetDailyGlobalTable(
	ctx context.Context,
	actorID string,
	gameCenterID string,
	now time.Time,
) (*game.DailyGlobalTable, error) {
	if strings.TrimSpace(actorID) == "" || strings.TrimSpace(gameCenterID) == "" {
		return nil, game.ErrInvalid
	}
	now = now.UTC()
	if err := r.processDailyRounds(ctx, now); err != nil {
		return nil, err
	}
	today := game.DailyDate(now)
	if err := r.ensureDailyRound(ctx, today); err != nil {
		return nil, err
	}
	yesterday := game.DailyDate(now.AddDate(0, 0, -1))
	if err := r.ensureDailyRound(ctx, yesterday); err != nil {
		return nil, err
	}
	if err := r.finalizeDailyRound(ctx, yesterday, now); err != nil {
		return nil, err
	}
	return r.loadDailyTable(ctx, today, yesterday, dailyPlayerDocumentID(gameCenterID), now)
}

func (r *FirestoreRepository) LockDailyGlobalPick(
	ctx context.Context,
	actorID string,
	gameCenterID string,
	roundDate string,
	pick uint64,
	now time.Time,
) (*game.DailyGlobalTable, error) {
	if strings.TrimSpace(actorID) == "" || strings.TrimSpace(gameCenterID) == "" || pick == 0 {
		return nil, game.ErrInvalid
	}
	closesAt, err := game.DailyClosesAt(roundDate)
	if err != nil {
		return nil, err
	}
	now = now.UTC()
	accountHash := dailyAccountDocumentID(actorID)
	playerHash := dailyPlayerDocumentID(gameCenterID)
	round := r.client.Collection(dailyRounds).Doc(roundDate)
	claim := r.dailyClaimRef(accountHash, roundDate)
	entry := round.Collection(dailyEntries).Doc(playerHash)
	pickValue := strconv.FormatUint(pick, 10)
	err = r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		roundSnapshot, roundErr := tx.Get(round)
		if roundErr != nil && status.Code(roundErr) != codes.NotFound {
			return roundErr
		}
		claimSnapshot, claimErr := tx.Get(claim)
		if claimErr != nil && status.Code(claimErr) != codes.NotFound {
			return claimErr
		}
		entrySnapshot, entryErr := tx.Get(entry)
		if entryErr != nil && status.Code(entryErr) != codes.NotFound {
			return entryErr
		}
		if claimErr == nil || entryErr == nil {
			if claimErr != nil || entryErr != nil {
				return game.ErrAlreadyLocked
			}
			var storedClaim dailyClaimDocument
			var storedEntry dailyEntryDocument
			if err := claimSnapshot.DataTo(&storedClaim); err != nil {
				return fmt.Errorf("decode daily claim: %w", err)
			}
			if err := entrySnapshot.DataTo(&storedEntry); err != nil {
				return fmt.Errorf("decode daily entry: %w", err)
			}
			if storedClaim.AccountHash == accountHash && storedClaim.PlayerHash == playerHash &&
				storedClaim.Pick == pickValue && storedEntry.AccountHash == accountHash && storedEntry.Pick == pickValue {
				return nil
			}
			return game.ErrAlreadyLocked
		}
		if roundDate != game.DailyDate(now) || !now.Before(closesAt) {
			return game.ErrRoundMismatch
		}
		if roundErr == nil {
			document, err := decodeDailyRound(roundDate, roundSnapshot)
			if err != nil {
				return err
			}
			if document.Status != game.DailyRoundOpen || !now.Before(document.ClosesAt) {
				return game.ErrRoundMismatch
			}
		} else if err := tx.Create(round, newDailyRoundDocument(closesAt)); err != nil {
			return err
		}
		if err := tx.Create(claim, dailyClaimDocument{
			AccountHash: accountHash,
			PlayerHash:  playerHash,
			Pick:        pickValue,
		}); err != nil {
			return err
		}
		return tx.Create(entry, newDailyEntryDocument(accountHash, pick))
	})
	if err != nil {
		return nil, translateError(err)
	}
	return r.GetDailyGlobalTable(ctx, actorID, gameCenterID, now)
}

func (r *FirestoreRepository) processDailyRounds(ctx context.Context, now time.Time) error {
	snapshots, err := r.client.Collection(dailyRounds).Where("cleanup_scheduled", "==", false).Documents(ctx).GetAll()
	if err != nil {
		return translateError(err)
	}
	for _, snapshot := range snapshots {
		document, err := decodeDailyRound(snapshot.Ref.ID, snapshot)
		if err != nil {
			return err
		}
		if !now.Before(document.ClosesAt) {
			// ponytail: v1 settles lazily here; move this scan to scheduled work when cutoff latency approaches the request timeout.
			if err := r.finalizeDailyRound(ctx, snapshot.Ref.ID, now); err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *FirestoreRepository) ensureDailyRound(ctx context.Context, date string) error {
	closesAt, err := game.DailyClosesAt(date)
	if err != nil {
		return err
	}
	_, err = r.client.Collection(dailyRounds).Doc(date).Create(ctx, newDailyRoundDocument(closesAt))
	if status.Code(err) == codes.AlreadyExists {
		return nil
	}
	return translateError(err)
}

func newDailyRoundDocument(closesAt time.Time) dailyRoundDocument {
	return dailyRoundDocument{
		ClosesAt:         closesAt,
		Status:           string(game.DailyRoundOpen),
		CleanupScheduled: false,
	}
}

func newDailyEntryDocument(accountHash string, pick uint64) dailyEntryDocument {
	return dailyEntryDocument{
		AccountHash: accountHash,
		Pick:        strconv.FormatUint(pick, 10),
		PickKey:     fmt.Sprintf("%020d", pick),
	}
}

func dailyAccountDocumentID(value string) string {
	return dailyIdentityDocumentID("account", value)
}

func dailyPlayerDocumentID(value string) string {
	return dailyIdentityDocumentID("player", value)
}

func dailyIdentityDocumentID(kind, value string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte("mini-match:daily:"+kind+"\x00"+value)))
}

func (r *FirestoreRepository) dailyClaimRef(accountHash, date string) *firestore.DocumentRef {
	return r.client.Collection(dailyClaims).Doc(accountHash).Collection(dailyClaimRounds).Doc(date)
}

func decodeDailyEntryDocument(playerHash string, document dailyEntryDocument) (game.DailyEntry, error) {
	pick, err := strconv.ParseUint(document.Pick, 10, 64)
	if err != nil || pick == 0 || document.PickKey != fmt.Sprintf("%020d", pick) {
		return game.DailyEntry{}, fmt.Errorf("decode daily entry %q: invalid pick", playerHash)
	}
	return game.DailyEntry{PlayerHash: playerHash, Pick: pick}, nil
}

func (r *FirestoreRepository) finalizeDailyRound(ctx context.Context, date string, now time.Time) error {
	closesAt, err := game.DailyClosesAt(date)
	if err != nil {
		return err
	}
	if now.Before(closesAt) {
		return nil
	}
	token, err := dailyCalculationToken()
	if err != nil {
		return err
	}
	round := r.client.Collection(dailyRounds).Doc(date)
	terminal := false
	claimed := false
	err = r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		terminal = false
		claimed = false
		snapshot, err := tx.Get(round)
		if err != nil {
			return err
		}
		document, err := decodeDailyRound(date, snapshot)
		if err != nil {
			return err
		}
		if dailyTerminal(document.Status) {
			terminal = true
			return nil
		}
		if now.Before(document.ClosesAt) {
			return nil
		}
		if document.Status == game.DailyRoundCalculating && document.CalculationLease.After(now) {
			return nil
		}
		if document.Status != game.DailyRoundOpen && document.Status != game.DailyRoundCalculating {
			return fmt.Errorf("decode daily round %q: invalid status %q", date, document.Status)
		}
		claimed = true
		return tx.Update(round, []firestore.Update{
			{Path: "status", Value: string(game.DailyRoundCalculating)},
			{Path: "calculation_token", Value: token},
			{Path: "calculation_lease_until", Value: now.Add(dailyCalcLease)},
		})
	})
	if err != nil {
		return translateError(err)
	}
	if terminal {
		return r.scheduleDailyCleanup(ctx, round)
	}
	if !claimed {
		return nil
	}
	entries := func(yield func(game.DailyEntry, error) bool) {
		documents := round.Collection(dailyEntries).OrderBy("pick_key", firestore.Asc).Documents(ctx)
		defer documents.Stop()
		for {
			snapshot, err := documents.Next()
			if errors.Is(err, iterator.Done) {
				return
			}
			if err != nil {
				yield(game.DailyEntry{}, err)
				return
			}
			var document dailyEntryDocument
			if err := snapshot.DataTo(&document); err != nil {
				yield(game.DailyEntry{}, fmt.Errorf("decode daily entry: %w", err))
				return
			}
			entry, err := decodeDailyEntryDocument(snapshot.Ref.ID, document)
			if err != nil {
				yield(game.DailyEntry{}, err)
				return
			}
			if !yield(entry, nil) {
				return
			}
		}
	}
	result, err := game.ResolveSortedDailyRound(entries)
	if err != nil {
		return err
	}
	finalizedAt := now
	err = r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(round)
		if err != nil {
			return err
		}
		document, err := decodeDailyRound(date, snapshot)
		if err != nil {
			return err
		}
		if dailyTerminal(document.Status) {
			return nil
		}
		if document.Status != game.DailyRoundCalculating || document.CalculationToken != token {
			return nil
		}
		var totalWins uint64
		var stats *firestore.DocumentRef
		if result.Status == game.DailyRoundWinner {
			stats = r.client.Collection(dailyPlayerStats).Doc(result.WinnerHash)
			statsSnapshot, err := tx.Get(stats)
			if err != nil && status.Code(err) != codes.NotFound {
				return err
			}
			if err == nil {
				var statsDocument dailyPlayerStatsDocument
				if err := statsSnapshot.DataTo(&statsDocument); err != nil {
					return fmt.Errorf("decode daily player stats: %w", err)
				}
				totalWins, err = parseOptionalUint64(statsDocument.TotalWins, "daily total wins")
				if err != nil {
					return err
				}
			}
			if totalWins == math.MaxUint64 {
				return game.ErrStatsExhausted
			}
		}
		updates := []firestore.Update{
			{Path: "status", Value: string(result.Status)},
			{Path: "entrant_count", Value: strconv.FormatUint(result.EntrantCount, 10)},
			{Path: "winning_pick", Value: optionalUint64(result.WinningPick)},
			{Path: "finalized_at", Value: finalizedAt},
			{Path: "cleanup_scheduled", Value: false},
			{Path: "calculation_token", Value: firestore.Delete},
			{Path: "calculation_lease_until", Value: firestore.Delete},
		}
		if err := tx.Update(round, updates); err != nil {
			return err
		}
		if stats != nil {
			return tx.Set(stats, dailyPlayerStatsDocument{TotalWins: strconv.FormatUint(totalWins+1, 10)})
		}
		return nil
	})
	if err != nil {
		return translateError(err)
	}
	return r.scheduleDailyCleanup(ctx, round)
}

func (r *FirestoreRepository) scheduleDailyCleanup(ctx context.Context, round *firestore.DocumentRef) error {
	snapshot, err := round.Get(ctx)
	if err != nil {
		return translateError(err)
	}
	document, err := decodeDailyRound(round.ID, snapshot)
	if err != nil {
		return err
	}
	if !dailyTerminal(document.Status) || document.CleanupScheduled {
		return nil
	}
	expiresAt := document.FinalizedAt.Add(dailyRetention)
	batch := r.client.Batch()
	count := 0
	flush := func() error {
		if count == 0 {
			return nil
		}
		if _, err := batch.Commit(ctx); err != nil {
			return err
		}
		batch = r.client.Batch()
		count = 0
		return nil
	}
	documents := round.Collection(dailyEntries).Documents(ctx)
	for {
		snapshot, err := documents.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			documents.Stop()
			return err
		}
		var entry dailyEntryDocument
		if err := snapshot.DataTo(&entry); err != nil {
			documents.Stop()
			return fmt.Errorf("decode daily entry: %w", err)
		}
		if count >= 448 {
			if err := flush(); err != nil {
				documents.Stop()
				return err
			}
		}
		batch.Update(snapshot.Ref, []firestore.Update{{Path: "expires_at", Value: expiresAt}})
		count++
		if entry.AccountHash != "" {
			batch.Set(
				r.dailyClaimRef(entry.AccountHash, round.ID),
				map[string]any{"expires_at": expiresAt},
				firestore.MergeAll,
			)
			count++
		}
	}
	documents.Stop()
	if err := flush(); err != nil {
		return err
	}
	_, err = round.Update(ctx, []firestore.Update{{Path: "cleanup_scheduled", Value: true}})
	return translateError(err)
}

func (r *FirestoreRepository) loadDailyTable(
	ctx context.Context,
	todayDate string,
	yesterdayDate string,
	playerHash string,
	now time.Time,
) (*game.DailyGlobalTable, error) {
	today, err := r.loadDailyRoundView(ctx, todayDate, playerHash)
	if err != nil {
		return nil, err
	}
	yesterday, err := r.loadDailyRoundView(ctx, yesterdayDate, playerHash)
	if err != nil {
		return nil, err
	}
	totalWins := uint64(0)
	snapshot, err := r.client.Collection(dailyPlayerStats).Doc(playerHash).Get(ctx)
	if err == nil {
		var document dailyPlayerStatsDocument
		if err := snapshot.DataTo(&document); err != nil {
			return nil, fmt.Errorf("decode daily player stats: %w", err)
		}
		totalWins, err = parseOptionalUint64(document.TotalWins, "daily total wins")
	}
	if err != nil && status.Code(err) != codes.NotFound {
		return nil, translateError(err)
	}
	return &game.DailyGlobalTable{ServerTime: now, Today: today, Yesterday: yesterday, TotalWins: totalWins}, nil
}

func (r *FirestoreRepository) loadDailyRoundView(
	ctx context.Context,
	date string,
	playerHash string,
) (game.DailyRoundView, error) {
	round := r.client.Collection(dailyRounds).Doc(date)
	snapshot, err := round.Get(ctx)
	if err != nil {
		return game.DailyRoundView{}, translateError(err)
	}
	document, err := decodeDailyRound(date, snapshot)
	if err != nil {
		return game.DailyRoundView{}, err
	}
	view := game.DailyRoundView{
		Date:         date,
		ClosesAt:     document.ClosesAt,
		Status:       document.Status,
		EntrantCount: document.EntrantCount,
		WinningPick:  document.WinningPick,
	}
	entrySnapshot, err := round.Collection(dailyEntries).Doc(playerHash).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return view, nil
	}
	if err != nil {
		return game.DailyRoundView{}, translateError(err)
	}
	var entry dailyEntryDocument
	if err := entrySnapshot.DataTo(&entry); err != nil {
		return game.DailyRoundView{}, fmt.Errorf("decode daily entry: %w", err)
	}
	decodedEntry, err := decodeDailyEntryDocument(playerHash, entry)
	if err != nil {
		return game.DailyRoundView{}, err
	}
	view.Pick = decodedEntry.Pick
	view.Won = document.Status == game.DailyRoundWinner && view.Pick == document.WinningPick
	return view, nil
}

type decodedDailyRound struct {
	ClosesAt         time.Time
	Status           game.DailyRoundStatus
	EntrantCount     uint64
	WinningPick      uint64
	FinalizedAt      time.Time
	CleanupScheduled bool
	CalculationToken string
	CalculationLease time.Time
}

func decodeDailyRound(date string, snapshot *firestore.DocumentSnapshot) (decodedDailyRound, error) {
	var document dailyRoundDocument
	if err := snapshot.DataTo(&document); err != nil {
		return decodedDailyRound{}, fmt.Errorf("decode daily round: %w", err)
	}
	expectedClosesAt, err := game.DailyClosesAt(date)
	if err != nil || !document.ClosesAt.Equal(expectedClosesAt) {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: invalid close time", date)
	}
	statusValue := game.DailyRoundStatus(document.Status)
	if statusValue != game.DailyRoundOpen && statusValue != game.DailyRoundCalculating && !dailyTerminal(statusValue) {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: invalid status %q", date, document.Status)
	}
	entrantCount, err := parseOptionalUint64(document.EntrantCount, "daily entrant count")
	if err != nil {
		return decodedDailyRound{}, err
	}
	winningPick, err := parseOptionalUint64(document.WinningPick, "daily winning pick")
	if err != nil {
		return decodedDailyRound{}, err
	}
	terminal := dailyTerminal(statusValue)
	if terminal && document.FinalizedAt.IsZero() {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: terminal round has no finalization time", date)
	}
	validResult := statusValue == game.DailyRoundEmpty && entrantCount == 0 && winningPick == 0 ||
		statusValue == game.DailyRoundInsufficient && entrantCount == 1 && winningPick == 0 ||
		statusValue == game.DailyRoundNoUnique && entrantCount >= 2 && winningPick == 0 ||
		statusValue == game.DailyRoundWinner && entrantCount >= 2 && winningPick != 0
	if terminal && !validResult {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: inconsistent result", date)
	}
	if !terminal && (entrantCount != 0 || winningPick != 0 || !document.FinalizedAt.IsZero() || document.CleanupScheduled) {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: unfinished round has result fields", date)
	}
	if statusValue == game.DailyRoundCalculating &&
		(document.CalculationToken == "" || document.CalculationLease.IsZero()) {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: calculating round has no lease", date)
	}
	if statusValue != game.DailyRoundCalculating &&
		(document.CalculationToken != "" || !document.CalculationLease.IsZero()) {
		return decodedDailyRound{}, fmt.Errorf("decode daily round %q: inactive calculation lease", date)
	}
	return decodedDailyRound{
		ClosesAt:         document.ClosesAt,
		Status:           statusValue,
		EntrantCount:     entrantCount,
		WinningPick:      winningPick,
		FinalizedAt:      document.FinalizedAt,
		CleanupScheduled: document.CleanupScheduled,
		CalculationToken: document.CalculationToken,
		CalculationLease: document.CalculationLease,
	}, nil
}

func dailyTerminal(status game.DailyRoundStatus) bool {
	return status == game.DailyRoundEmpty || status == game.DailyRoundInsufficient ||
		status == game.DailyRoundNoUnique || status == game.DailyRoundWinner
}

func parseOptionalUint64(value, name string) (uint64, error) {
	if value == "" {
		return 0, nil
	}
	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("decode %s: %w", name, err)
	}
	return parsed, nil
}

func dailyCalculationToken() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", fmt.Errorf("generate Daily calculation token: %w", err)
	}
	return hex.EncodeToString(value[:]), nil
}
