package store

import (
	"context"
	"fmt"
	"math"
	"strconv"

	"cloud.google.com/go/firestore"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	privateTables = "tables"
	publicTables  = "table_views"
	joinCodes     = "join_codes"
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
		if err := update(table); err != nil {
			return err
		}
		if err := tx.Set(private, privateDocument(table)); err != nil {
			return err
		}
		if err := tx.Set(public, publicDocument(table)); err != nil {
			return err
		}
		updated = table
		return nil
	})
	if err != nil {
		return nil, translateError(err)
	}
	return updated, nil
}

type joinCodeDocument struct {
	TableID string `firestore:"table_id"`
}

type tableDocument struct {
	Name          string           `firestore:"name"`
	JoinCode      string           `firestore:"join_code"`
	HostID        string           `firestore:"host_player_id"`
	Players       []playerDocument `firestore:"players"`
	CurrentRound  roundDocument    `firestore:"current_round"`
	LastResult    *resultDocument  `firestore:"last_result,omitempty"`
	WinnerID      string           `firestore:"winner_player_id,omitempty"`
	Version       string           `firestore:"state_version"`
	EventSequence string           `firestore:"event_sequence"`
}

type playerDocument struct {
	ID     string `firestore:"id"`
	Name   string `firestore:"display_name"`
	Score  int64  `firestore:"wins"`
	Locked bool   `firestore:"locked"`
	Pick   string `firestore:"pick"`
}

type roundDocument struct {
	Number int64  `firestore:"number"`
	Phase  string `firestore:"phase"`
}

type resultDocument struct {
	RoundNumber int64               `firestore:"round_number"`
	Selections  []selectionDocument `firestore:"selections"`
	WinnerID    string              `firestore:"winner_player_id,omitempty"`
}

type selectionDocument struct {
	PlayerID string `firestore:"player_id"`
	Pick     string `firestore:"pick"`
}

type safeTableDocument struct {
	ID             string               `firestore:"id"`
	Name           string               `firestore:"name"`
	JoinCode       string               `firestore:"join_code"`
	HostID         string               `firestore:"host_player_id"`
	PlayerIDs      []string             `firestore:"player_ids"`
	Players        []safePlayerDocument `firestore:"players"`
	State          string               `firestore:"state"`
	CurrentRound   *roundDocument       `firestore:"current_round,omitempty"`
	LastResult     *resultDocument      `firestore:"last_result,omitempty"`
	WinsToFinish   int64                `firestore:"wins_to_finish"`
	Version        string               `firestore:"state_version"`
	EventSequence  string               `firestore:"event_sequence"`
	WinnerPlayerID string               `firestore:"winner_player_id,omitempty"`
}

type safePlayerDocument struct {
	ID     string `firestore:"id"`
	Name   string `firestore:"display_name"`
	Score  int64  `firestore:"wins"`
	Locked bool   `firestore:"locked"`
}

func privateDocument(table *game.Table) tableDocument {
	document := tableDocument{
		Name:          table.Name,
		JoinCode:      table.JoinCode,
		HostID:        table.HostID,
		Players:       make([]playerDocument, 0, len(table.Players)),
		CurrentRound:  encodeRound(table.CurrentRound),
		LastResult:    encodeResult(table.LastResult),
		WinnerID:      table.WinnerID,
		Version:       strconv.FormatUint(table.Version, 10),
		EventSequence: strconv.FormatUint(table.EventSequence, 10),
	}
	for _, player := range table.Players {
		document.Players = append(document.Players, playerDocument{
			ID:     player.ID,
			Name:   player.Name,
			Score:  int64(player.Score),
			Locked: player.Locked,
			Pick:   strconv.FormatUint(player.Pick, 10),
		})
	}
	return document
}

func publicDocument(table *game.Table) safeTableDocument {
	document := safeTableDocument{
		ID:             table.ID,
		Name:           table.Name,
		JoinCode:       table.JoinCode,
		HostID:         table.HostID,
		PlayerIDs:      make([]string, 0, len(table.Players)),
		Players:        make([]safePlayerDocument, 0, len(table.Players)),
		State:          "active",
		WinsToFinish:   game.WinningScore,
		Version:        strconv.FormatUint(table.Version, 10),
		EventSequence:  strconv.FormatUint(table.EventSequence, 10),
		WinnerPlayerID: table.WinnerID,
		LastResult:     encodeResult(table.LastResult),
	}
	if table.WinnerID == "" {
		round := encodeRound(table.CurrentRound)
		document.CurrentRound = &round
	} else {
		document.State = "finished"
	}
	for _, player := range table.Players {
		document.PlayerIDs = append(document.PlayerIDs, player.ID)
		document.Players = append(document.Players, safePlayerDocument{
			ID:     player.ID,
			Name:   player.Name,
			Score:  int64(player.Score),
			Locked: player.Locked,
		})
	}
	return document
}

func encodeRound(round game.Round) roundDocument {
	phase := "accepting_picks"
	if round.Phase == game.RoundReady {
		phase = "ready_to_reveal"
	}
	return roundDocument{Number: int64(round.Number), Phase: phase}
}

func encodeResult(result *game.Result) *resultDocument {
	if result == nil {
		return nil
	}
	document := &resultDocument{
		RoundNumber: int64(result.RoundNumber),
		Selections:  make([]selectionDocument, 0, len(result.Selections)),
		WinnerID:    result.WinnerID,
	}
	for _, selection := range result.Selections {
		document.Selections = append(document.Selections, selectionDocument{
			PlayerID: selection.PlayerID,
			Pick:     strconv.FormatUint(selection.Pick, 10),
		})
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
	roundNumber, err := uint32Value(document.CurrentRound.Number, "round number")
	if err != nil {
		return nil, err
	}
	phase, err := decodePhase(document.CurrentRound.Phase)
	if err != nil {
		return nil, err
	}
	version, err := strconv.ParseUint(document.Version, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("decode state version: %w", err)
	}
	eventSequence, err := strconv.ParseUint(document.EventSequence, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("decode event sequence: %w", err)
	}
	table := &game.Table{
		ID:            id,
		Name:          document.Name,
		JoinCode:      document.JoinCode,
		HostID:        document.HostID,
		Players:       make([]*game.Player, 0, len(document.Players)),
		CurrentRound:  game.Round{Number: roundNumber, Phase: phase},
		WinnerID:      document.WinnerID,
		Version:       version,
		EventSequence: eventSequence,
	}
	for _, player := range document.Players {
		score, err := uint32Value(player.Score, "player wins")
		if err != nil {
			return nil, err
		}
		pick, err := strconv.ParseUint(player.Pick, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("decode player pick: %w", err)
		}
		table.Players = append(table.Players, &game.Player{
			ID:     player.ID,
			Name:   player.Name,
			Score:  score,
			Locked: player.Locked,
			Pick:   pick,
		})
	}
	if document.LastResult != nil {
		result, err := decodeResult(document.LastResult)
		if err != nil {
			return nil, err
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
	for _, selection := range document.Selections {
		pick, err := strconv.ParseUint(selection.Pick, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("decode result pick: %w", err)
		}
		result.Selections = append(result.Selections, game.Selection{
			PlayerID: selection.PlayerID,
			Pick:     pick,
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
