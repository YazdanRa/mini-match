package store

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	privateTables = "tables"
	publicTables  = "table_views"
	joinCodes     = "join_codes"
	playerStats   = "player_stats"
)

type FirestoreRepository struct {
	client *firestore.Client
}

func NewFirestoreRepository(client *firestore.Client) *FirestoreRepository {
	return &FirestoreRepository{client: client}
}

func (r *FirestoreRepository) Create(ctx context.Context, table *game.Table) error {
	private := r.client.Collection(privateTables).Doc(table.ID)
	public := r.client.Collection(publicTables).Doc(table.ID)
	code := r.client.Collection(joinCodes).Doc(table.JoinCode)
	err := r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		if err := tx.Create(private, privateDocument(table)); err != nil {
			return err
		}
		if err := tx.Create(public, publicDocument(table)); err != nil {
			return err
		}
		return tx.Create(code, joinCodeDocument{TableID: table.ID})
	})
	return translateError(err)
}

func (r *FirestoreRepository) Get(ctx context.Context, id string) (*game.Table, error) {
	snapshot, err := r.client.Collection(privateTables).Doc(id).Get(ctx)
	if err != nil {
		return nil, translateError(err)
	}
	return decodeTable(id, snapshot)
}

func (r *FirestoreRepository) GetByJoinCode(ctx context.Context, joinCode string) (*game.Table, error) {
	snapshot, err := r.client.Collection(joinCodes).Doc(joinCode).Get(ctx)
	if err != nil {
		return nil, translateError(err)
	}
	var code joinCodeDocument
	if err := snapshot.DataTo(&code); err != nil {
		return nil, fmt.Errorf("decode join code: %w", err)
	}
	return r.Get(ctx, code.TableID)
}

func (r *FirestoreRepository) Update(ctx context.Context, id string, update func(*game.Table) error) (*game.Table, error) {
	private := r.client.Collection(privateTables).Doc(id)
	public := r.client.Collection(publicTables).Doc(id)
	var updated *game.Table
	err := r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(private)
		if err != nil {
			return err
		}
		table, err := decodeTable(id, snapshot)
		if err != nil {
			return err
		}
		version := table.Version
		if err := update(table); err != nil {
			return err
		}
		if err := tx.Set(private, privateDocument(table)); err != nil {
			return err
		}
		if table.Version != version {
			if err := tx.Set(public, publicDocument(table)); err != nil {
				return err
			}
		}
		updated = table
		return nil
	})
	if err != nil {
		return nil, translateError(err)
	}
	return updated, nil
}

func (r *FirestoreRepository) RevealRound(
	ctx context.Context,
	id string,
	reveal func(*game.Table) error,
) (*game.Table, error) {
	private := r.client.Collection(privateTables).Doc(id)
	public := r.client.Collection(publicTables).Doc(id)
	var updated *game.Table
	err := r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(private)
		if err != nil {
			return err
		}
		table, err := decodeTable(id, snapshot)
		if err != nil {
			return err
		}
		previousResult := table.LastResult
		if err := reveal(table); err != nil {
			return err
		}
		if table.LastResult == nil || table.LastResult == previousResult {
			return game.ErrNotReady
		}

		gameCenterIDs := roundGameCenterIDs(table)
		stats := make(map[string]game.PlayerStats, len(gameCenterIDs))
		for _, gameCenterID := range gameCenterIDs {
			reference := r.client.Collection(playerStats).Doc(statsDocumentID(gameCenterID))
			snapshot, err := tx.Get(reference)
			if status.Code(err) == codes.NotFound {
				continue
			}
			if err != nil {
				return err
			}
			current, err := decodePlayerStats(snapshot)
			if err != nil {
				return err
			}
			stats[gameCenterID] = current
		}
		if err := table.ApplyRoundStats(stats); err != nil {
			return err
		}
		encodedStats := make(map[string]playerStatsDocument, len(stats))
		for gameCenterID, current := range stats {
			encodedStats[gameCenterID] = encodePlayerStats(current)
		}

		if err := tx.Set(private, privateDocument(table)); err != nil {
			return err
		}
		if err := tx.Set(public, publicDocument(table)); err != nil {
			return err
		}
		for gameCenterID, document := range encodedStats {
			if err := tx.Set(
				r.client.Collection(playerStats).Doc(statsDocumentID(gameCenterID)),
				document,
			); err != nil {
				return err
			}
		}
		updated = table
		return nil
	})
	if err != nil {
		return nil, translateError(err)
	}
	return updated, nil
}

func (r *FirestoreRepository) DeleteProfile(ctx context.Context, playerID string) error {
	err := r.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		var snapshots []*firestore.DocumentSnapshot
		seen := make(map[string]struct{})
		for _, field := range []string{"player_ids", "result_player_ids"} {
			matches, err := tx.Documents(
				r.client.Collection(publicTables).Where(field, "array-contains", playerID),
			).GetAll()
			if err != nil {
				return err
			}
			for _, snapshot := range matches {
				if _, exists := seen[snapshot.Ref.ID]; exists {
					continue
				}
				seen[snapshot.Ref.ID] = struct{}{}
				snapshots = append(snapshots, snapshot)
			}
		}
		statsMatches, err := tx.Documents(
			r.client.Collection(playerStats).Where("player_ids", "array-contains", playerID),
		).GetAll()
		if err != nil {
			return err
		}
		tables := make([]*game.Table, 0, len(snapshots))
		statsReferences := make(map[string]*firestore.DocumentRef, len(statsMatches))
		for _, snapshot := range statsMatches {
			statsReferences[snapshot.Ref.ID] = snapshot.Ref
		}
		for _, public := range snapshots {
			private := r.client.Collection(privateTables).Doc(public.Ref.ID)
			snapshot, err := tx.Get(private)
			if err != nil {
				return err
			}
			table, err := decodeTable(public.Ref.ID, snapshot)
			if err != nil {
				return err
			}
			tables = append(tables, table)
			for _, player := range table.Players {
				if player.ID == playerID && player.GameCenterID != "" {
					reference := r.client.Collection(playerStats).Doc(statsDocumentID(player.GameCenterID))
					statsReferences[reference.ID] = reference
				}
			}
		}
		for _, reference := range statsReferences {
			if _, err := tx.Get(reference); err != nil && status.Code(err) != codes.NotFound {
				return err
			}
		}
		for _, table := range tables {
			replacementID := "deleted:" + statsDocumentID(playerID+"\x00"+table.ID)
			if err := table.DeletePlayerProfile(playerID, replacementID); err != nil {
				if errors.Is(err, game.ErrNotFound) {
					continue
				}
				return err
			}
			if err := tx.Set(
				r.client.Collection(privateTables).Doc(table.ID),
				privateDocument(table),
			); err != nil {
				return err
			}
			if err := tx.Set(
				r.client.Collection(publicTables).Doc(table.ID),
				publicDocument(table),
			); err != nil {
				return err
			}
		}
		for _, reference := range statsReferences {
			if err := tx.Delete(reference); err != nil {
				return err
			}
		}
		return nil
	})
	return translateError(err)
}

type joinCodeDocument struct {
	TableID string `firestore:"table_id"`
}

type playerStatsDocument struct {
	LegacyWins       int64    `firestore:"wins,omitempty"`
	TotalRoundWins   string   `firestore:"total_round_wins,omitempty"`
	CurrentWinStreak int64    `firestore:"current_win_streak"`
	BestWinStreak    int64    `firestore:"best_win_streak"`
	PlayerIDs        []string `firestore:"player_ids"`
}

type tableDocument struct {
	Name               string           `firestore:"name"`
	JoinCode           string           `firestore:"join_code"`
	HostID             string           `firestore:"host_player_id"`
	Players            []playerDocument `firestore:"players"`
	CurrentRound       *roundDocument   `firestore:"current_round,omitempty"`
	LastResult         *resultDocument  `firestore:"last_result,omitempty"`
	WinnerID           string           `firestore:"winner_player_id,omitempty"`
	WinnerLifetimeWins string           `firestore:"winner_lifetime_wins,omitempty"`
	Version            string           `firestore:"state_version"`
	EventSequence      string           `firestore:"event_sequence"`
}

type playerDocument struct {
	ID                string    `firestore:"id"`
	GameCenterID      string    `firestore:"game_center_id,omitempty"`
	Name              string    `firestore:"display_name"`
	Avatar            string    `firestore:"avatar,omitempty"`
	Score             int64     `firestore:"wins,omitempty"`
	Locked            bool      `firestore:"locked"`
	Pick              string    `firestore:"pick"`
	PresenceExpiresAt time.Time `firestore:"presence_expires_at,omitempty"`
}

type roundDocument struct {
	Number int64  `firestore:"number"`
	Phase  string `firestore:"phase"`
}

type resultDocument struct {
	RoundNumber         int64               `firestore:"round_number"`
	Selections          []selectionDocument `firestore:"selections"`
	WinnerID            string              `firestore:"winner_player_id,omitempty"`
	WinnerTotalWins     string              `firestore:"winner_total_wins,omitempty"`
	WinnerWinStreak     int64               `firestore:"winner_win_streak,omitempty"`
	WinnerBestWinStreak int64               `firestore:"winner_best_win_streak,omitempty"`
}

type selectionDocument struct {
	PlayerID    string `firestore:"player_id"`
	DisplayName string `firestore:"display_name,omitempty"`
	Pick        string `firestore:"pick"`
}

type safeTableDocument struct {
	ID              string               `firestore:"id"`
	Name            string               `firestore:"name"`
	JoinCode        string               `firestore:"join_code"`
	HostID          string               `firestore:"host_player_id"`
	PlayerIDs       []string             `firestore:"player_ids"`
	ResultPlayerIDs []string             `firestore:"result_player_ids,omitempty"`
	Players         []safePlayerDocument `firestore:"players"`
	State           string               `firestore:"state"`
	CurrentRound    *roundDocument       `firestore:"current_round,omitempty"`
	LastResult      *resultDocument      `firestore:"last_result,omitempty"`
	WinsToFinish    int64                `firestore:"wins_to_finish,omitempty"`
	Version         string               `firestore:"state_version"`
	EventSequence   string               `firestore:"event_sequence"`
	WinnerPlayerID  string               `firestore:"winner_player_id,omitempty"`
}

type safePlayerDocument struct {
	ID     string `firestore:"id"`
	Name   string `firestore:"display_name"`
	Avatar string `firestore:"avatar,omitempty"`
	Score  int64  `firestore:"wins,omitempty"`
	Locked bool   `firestore:"locked"`
}

func privateDocument(table *game.Table) tableDocument {
	document := tableDocument{
		Name:               table.Name,
		JoinCode:           table.JoinCode,
		HostID:             table.HostID,
		Players:            make([]playerDocument, 0, len(table.Players)),
		CurrentRound:       encodeRound(table.CurrentRound),
		LastResult:         encodeResult(table.LastResult),
		WinnerLifetimeWins: optionalUint64(table.WinnerLifetimeWins),
		Version:            strconv.FormatUint(table.Version, 10),
		EventSequence:      strconv.FormatUint(table.EventSequence, 10),
	}
	for _, player := range table.Players {
		document.Players = append(document.Players, playerDocument{
			ID:                player.ID,
			GameCenterID:      player.GameCenterID,
			Name:              player.Name,
			Avatar:            player.Avatar,
			Locked:            player.Locked,
			Pick:              strconv.FormatUint(player.Pick, 10),
			PresenceExpiresAt: player.PresenceExpiresAt,
		})
	}
	return document
}

func publicDocument(table *game.Table) safeTableDocument {
	document := safeTableDocument{
		ID:            table.ID,
		Name:          table.Name,
		JoinCode:      table.JoinCode,
		HostID:        table.HostID,
		PlayerIDs:     make([]string, 0, len(table.Players)),
		Players:       make([]safePlayerDocument, 0, len(table.Players)),
		State:         "active",
		Version:       strconv.FormatUint(table.Version, 10),
		EventSequence: strconv.FormatUint(table.EventSequence, 10),
		LastResult:    encodePublicResult(table.LastResult),
	}
	document.CurrentRound = encodeRound(table.CurrentRound)
	for _, player := range table.Players {
		document.PlayerIDs = append(document.PlayerIDs, player.ID)
		document.Players = append(document.Players, safePlayerDocument{
			ID:     player.ID,
			Name:   player.Name,
			Avatar: player.Avatar,
			Locked: player.Locked,
		})
	}
	if table.LastResult != nil {
		document.ResultPlayerIDs = make([]string, 0, len(table.LastResult.Selections))
		for _, selection := range table.LastResult.Selections {
			document.ResultPlayerIDs = append(document.ResultPlayerIDs, selection.PlayerID)
		}
	}
	return document
}

func encodeRound(round *game.Round) *roundDocument {
	if round == nil {
		return nil
	}
	phase := "accepting_picks"
	if round.Phase == game.RoundReady {
		phase = "ready_to_reveal"
	}
	return &roundDocument{Number: int64(round.Number), Phase: phase}
}

func optionalUint64(value uint64) string {
	if value == 0 {
		return ""
	}
	return strconv.FormatUint(value, 10)
}

func statsDocumentID(gameCenterID string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(gameCenterID)))
}

func roundGameCenterIDs(table *game.Table) []string {
	if table.LastResult == nil {
		return nil
	}
	participants := make(map[string]struct{}, len(table.LastResult.Selections))
	for _, selection := range table.LastResult.Selections {
		participants[selection.PlayerID] = struct{}{}
	}
	identities := make(map[string]struct{}, len(participants))
	for _, player := range table.Players {
		if _, participated := participants[player.ID]; participated && player.GameCenterID != "" {
			identities[player.GameCenterID] = struct{}{}
		}
	}
	result := make([]string, 0, len(identities))
	for identity := range identities {
		result = append(result, identity)
	}
	sort.Strings(result)
	return result
}

func decodePlayerStats(snapshot *firestore.DocumentSnapshot) (game.PlayerStats, error) {
	var document playerStatsDocument
	if err := snapshot.DataTo(&document); err != nil {
		return game.PlayerStats{}, fmt.Errorf("decode player stats: %w", err)
	}
	return decodePlayerStatsDocument(document)
}

func decodePlayerStatsDocument(document playerStatsDocument) (game.PlayerStats, error) {
	if document.CurrentWinStreak < 0 || document.CurrentWinStreak > math.MaxUint32 ||
		document.BestWinStreak < 0 || document.BestWinStreak > math.MaxUint32 {
		return game.PlayerStats{}, fmt.Errorf("decode player stats: streak counter is out of range")
	}
	totalWins := uint64(0)
	if document.TotalRoundWins != "" {
		var err error
		totalWins, err = strconv.ParseUint(document.TotalRoundWins, 10, 64)
		if err != nil {
			return game.PlayerStats{}, fmt.Errorf("decode player stats total round wins: %w", err)
		}
	}
	return game.PlayerStats{
		TotalWins:        totalWins,
		CurrentWinStreak: uint32(document.CurrentWinStreak),
		BestWinStreak:    uint32(document.BestWinStreak),
		PlayerIDs:        document.PlayerIDs,
	}, nil
}

func encodePlayerStats(stats game.PlayerStats) playerStatsDocument {
	return playerStatsDocument{
		TotalRoundWins:   optionalUint64(stats.TotalWins),
		CurrentWinStreak: int64(stats.CurrentWinStreak),
		BestWinStreak:    int64(stats.BestWinStreak),
		PlayerIDs:        stats.PlayerIDs,
	}
}

func encodeResult(result *game.Result) *resultDocument {
	if result == nil {
		return nil
	}
	document := &resultDocument{
		RoundNumber:         int64(result.RoundNumber),
		Selections:          make([]selectionDocument, 0, len(result.Selections)),
		WinnerID:            result.WinnerID,
		WinnerTotalWins:     optionalUint64(result.WinnerTotalWins),
		WinnerWinStreak:     int64(result.WinnerWinStreak),
		WinnerBestWinStreak: int64(result.WinnerBestWinStreak),
	}
	for _, selection := range result.Selections {
		document.Selections = append(document.Selections, selectionDocument{
			PlayerID:    selection.PlayerID,
			DisplayName: selection.DisplayName,
			Pick:        strconv.FormatUint(selection.Pick, 10),
		})
	}
	return document
}

func encodePublicResult(result *game.Result) *resultDocument {
	document := encodeResult(result)
	if document != nil {
		document.WinnerTotalWins = ""
		document.WinnerWinStreak = 0
		document.WinnerBestWinStreak = 0
	}
	return document
}

func decodeTable(id string, snapshot *firestore.DocumentSnapshot) (*game.Table, error) {
	var document tableDocument
	if err := snapshot.DataTo(&document); err != nil {
		return nil, fmt.Errorf("decode table: %w", err)
	}
	return decodeDocument(id, document)
}

func decodeDocument(id string, document tableDocument) (*game.Table, error) {
	legacyFinished := document.WinnerID != ""
	var currentRound *game.Round
	if document.CurrentRound != nil && !legacyFinished {
		roundNumber, err := uint32Value(document.CurrentRound.Number, "round number")
		if err != nil {
			return nil, err
		}
		phase, err := decodePhase(document.CurrentRound.Phase)
		if err != nil {
			return nil, err
		}
		currentRound = &game.Round{Number: roundNumber, Phase: phase}
	}
	if legacyFinished {
		if document.LastResult == nil {
			return nil, fmt.Errorf("decode finished table without a last result")
		}
	}
	version, err := strconv.ParseUint(document.Version, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("decode state version: %w", err)
	}
	eventSequence, err := strconv.ParseUint(document.EventSequence, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("decode event sequence: %w", err)
	}
	winnerLifetimeWins := uint64(0)
	if document.WinnerLifetimeWins != "" {
		winnerLifetimeWins, err = strconv.ParseUint(document.WinnerLifetimeWins, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("decode winner lifetime wins: %w", err)
		}
	}
	table := &game.Table{
		ID:                 id,
		Name:               document.Name,
		JoinCode:           document.JoinCode,
		HostID:             document.HostID,
		Players:            make([]*game.Player, 0, len(document.Players)),
		CurrentRound:       currentRound,
		WinnerLifetimeWins: winnerLifetimeWins,
		Version:            version,
		EventSequence:      eventSequence,
	}
	for _, player := range document.Players {
		pick, err := strconv.ParseUint(player.Pick, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("decode player pick: %w", err)
		}
		if legacyFinished {
			pick = 0
		}
		table.Players = append(table.Players, &game.Player{
			ID:                player.ID,
			GameCenterID:      player.GameCenterID,
			Name:              player.Name,
			Avatar:            player.Avatar,
			Locked:            player.Locked && !legacyFinished,
			Pick:              pick,
			PresenceExpiresAt: player.PresenceExpiresAt,
		})
	}
	if document.LastResult != nil {
		result, err := decodeResult(document.LastResult)
		if err != nil {
			return nil, err
		}
		names := make(map[string]string, len(table.Players))
		for _, player := range table.Players {
			names[player.ID] = player.Name
		}
		for index := range result.Selections {
			if result.Selections[index].DisplayName == "" {
				result.Selections[index].DisplayName = names[result.Selections[index].PlayerID]
			}
		}
		table.LastResult = result
	}
	return table, nil
}

func decodeResult(document *resultDocument) (*game.Result, error) {
	roundNumber, err := uint32Value(document.RoundNumber, "result round number")
	if err != nil {
		return nil, err
	}
	result := &game.Result{
		RoundNumber: roundNumber,
		Selections:  make([]game.Selection, 0, len(document.Selections)),
		WinnerID:    document.WinnerID,
	}
	if document.WinnerTotalWins != "" {
		result.WinnerTotalWins, err = strconv.ParseUint(document.WinnerTotalWins, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("decode winner total wins: %w", err)
		}
	}
	if document.WinnerWinStreak < 0 || document.WinnerWinStreak > math.MaxUint32 ||
		document.WinnerBestWinStreak < 0 || document.WinnerBestWinStreak > math.MaxUint32 {
		return nil, fmt.Errorf("decode winner win streak: counter is out of range")
	}
	result.WinnerWinStreak = uint32(document.WinnerWinStreak)
	result.WinnerBestWinStreak = uint32(document.WinnerBestWinStreak)
	for _, selection := range document.Selections {
		pick, err := strconv.ParseUint(selection.Pick, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("decode result pick: %w", err)
		}
		result.Selections = append(result.Selections, game.Selection{
			PlayerID:    selection.PlayerID,
			DisplayName: selection.DisplayName,
			Pick:        pick,
		})
	}
	return result, nil
}

func decodePhase(value string) (game.RoundPhase, error) {
	switch value {
	case "accepting_picks":
		return game.RoundOpen, nil
	case "ready_to_reveal":
		return game.RoundReady, nil
	default:
		return 0, fmt.Errorf("decode round phase %q", value)
	}
}

func uint32Value(value int64, name string) (uint32, error) {
	if value < 0 || value > math.MaxUint32 {
		return 0, fmt.Errorf("decode %s: %d is out of range", name, value)
	}
	return uint32(value), nil
}

func translateError(err error) error {
	switch status.Code(err) {
	case codes.NotFound:
		return fmt.Errorf("%w: Firestore document", game.ErrNotFound)
	case codes.AlreadyExists:
		return fmt.Errorf("%w: Firestore document", game.ErrAlreadyExists)
	default:
		return err
	}
}
