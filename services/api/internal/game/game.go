package game

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
)

const WinningScore = 5

var (
	ErrAlreadyExists = errors.New("already exists")
	ErrAlreadyLocked = errors.New("pick already locked")
	ErrFinished      = errors.New("table is finished")
	ErrForbidden     = errors.New("only the host can start the round")
	ErrInvalid       = errors.New("invalid input")
	ErrNotFound      = errors.New("not found")
	ErrNotReady      = errors.New("every player must lock a pick")
	ErrRoundMismatch = errors.New("round number does not match")
)

type RoundPhase uint8

const (
	RoundOpen RoundPhase = iota
	RoundReady
)

type Table struct {
	ID            string
	Name          string
	JoinCode      string
	HostID        string
	Players       []*Player
	CurrentRound  Round
	LastResult    *Result
	WinnerID      string
	Version       uint64
	EventSequence uint64
}

type Player struct {
	ID     string
	Name   string
	Score  uint32
	Locked bool
	Pick   uint64
}

type Round struct {
	Number uint32
	Phase  RoundPhase
}

type Result struct {
	RoundNumber uint32
	Selections  []Selection
	WinnerID    string
}

type Selection struct {
	PlayerID string
	Pick     uint64
}

func NewTable(id, name, joinCode, hostID, hostName string) (*Table, error) {
	if blank(id) || blank(name) || blank(joinCode) || blank(hostID) || blank(hostName) {
		return nil, ErrInvalid
	}
	return &Table{
		ID:            id,
		Name:          strings.TrimSpace(name),
		JoinCode:      joinCode,
		HostID:        hostID,
		Players:       []*Player{{ID: hostID, Name: strings.TrimSpace(hostName)}},
		CurrentRound:  Round{Number: 1, Phase: RoundOpen},
		Version:       1,
		EventSequence: 1,
	}, nil
}

func (t *Table) Join(playerID, name string) error {
	if blank(playerID) || blank(name) {
		return ErrInvalid
	}
	if t.WinnerID != "" {
		return ErrFinished
	}
	if t.player(playerID) != nil {
		return ErrAlreadyExists
	}
	t.Players = append(t.Players, &Player{ID: playerID, Name: strings.TrimSpace(name)})
	if t.CurrentRound.Phase == RoundReady {
		t.CurrentRound.Phase = RoundOpen
	}
	t.changed()
	return nil
}

func (t *Table) LockPick(playerID string, pick uint64, roundNumber uint32) error {
	if t.WinnerID != "" {
		return ErrFinished
	}
	player := t.player(playerID)
	if player == nil {
		return ErrNotFound
	}
	if roundNumber != t.CurrentRound.Number {
		return ErrRoundMismatch
	}
	if player.Locked {
		return ErrAlreadyLocked
	}
	player.Pick = pick
	player.Locked = true
	t.CurrentRound.Phase = RoundReady
	for _, current := range t.Players {
		if !current.Locked {
			t.CurrentRound.Phase = RoundOpen
			break
		}
	}
	t.changed()
	return nil
}

func (t *Table) StartRound(actorID string, roundNumber uint32) error {
	if t.WinnerID != "" {
		return ErrFinished
	}
	if actorID != t.HostID {
		return ErrForbidden
	}
	if t.CurrentRound.Number != roundNumber {
		return ErrRoundMismatch
	}
	if t.CurrentRound.Phase != RoundReady {
		return ErrNotReady
	}
	for _, player := range t.Players {
		if !player.Locked {
			return ErrNotReady
		}
	}

	counts := make(map[uint64]int, len(t.Players))
	result := &Result{
		RoundNumber: roundNumber,
		Selections:  make([]Selection, 0, len(t.Players)),
	}
	for _, player := range t.Players {
		counts[player.Pick]++
		result.Selections = append(result.Selections, Selection{PlayerID: player.ID, Pick: player.Pick})
	}
	var (
		lowest uint64
		found  bool
	)
	for pick, count := range counts {
		if count == 1 && (!found || pick < lowest) {
			lowest, found = pick, true
		}
	}
	if found {
		for _, player := range t.Players {
			if player.Pick == lowest {
				result.WinnerID = player.ID
				player.Score++
				if player.Score == WinningScore {
					t.WinnerID = player.ID
				}
				break
			}
		}
	}
	t.LastResult = result
	for _, player := range t.Players {
		player.Locked = false
		player.Pick = 0
	}
	if t.WinnerID == "" {
		t.CurrentRound = Round{Number: roundNumber + 1, Phase: RoundOpen}
	}
	t.changed()
	return nil
}

func (t *Table) player(id string) *Player {
	for _, player := range t.Players {
		if player.ID == id {
			return player
		}
	}
	return nil
}

func (t *Table) HasPlayer(id string) bool {
	return t.player(id) != nil
}

func (t *Table) changed() {
	t.Version++
	t.EventSequence++
}

func blank(value string) bool {
	return strings.TrimSpace(value) == ""
}

type Repository interface {
	Create(context.Context, *Table) error
	Get(context.Context, string) (*Table, error)
	GetByJoinCode(context.Context, string) (*Table, error)
	Update(context.Context, string, func(*Table) error) (*Table, error)
}

type MemoryRepository struct {
	mu     sync.Mutex
	tables map[string]*Table
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{tables: make(map[string]*Table)}
}

func (r *MemoryRepository) Create(_ context.Context, table *Table) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, existing := range r.tables {
		if existing.ID == table.ID || existing.JoinCode == table.JoinCode {
			return fmt.Errorf("%w: table or join code", ErrAlreadyExists)
		}
	}
	r.tables[table.ID] = clone(table)
	return nil
}

func (r *MemoryRepository) Get(_ context.Context, id string) (*Table, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	table, exists := r.tables[id]
	if !exists {
		return nil, fmt.Errorf("%w: table %q", ErrNotFound, id)
	}
	return clone(table), nil
}

func (r *MemoryRepository) GetByJoinCode(_ context.Context, joinCode string) (*Table, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	// ponytail: linear lookup is enough for local tests; Firestore owns indexed lookup in production.
	for _, table := range r.tables {
		if table.JoinCode == joinCode {
			return clone(table), nil
		}
	}
	return nil, fmt.Errorf("%w: join code %q", ErrNotFound, joinCode)
}

func (r *MemoryRepository) Update(_ context.Context, id string, update func(*Table) error) (*Table, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	table, exists := r.tables[id]
	if !exists {
		return nil, fmt.Errorf("%w: table %q", ErrNotFound, id)
	}
	next := clone(table)
	if err := update(next); err != nil {
		return nil, err
	}
	r.tables[id] = next
	return clone(next), nil
}

func clone(table *Table) *Table {
	copy := *table
	copy.Players = make([]*Player, len(table.Players))
	for i, player := range table.Players {
		playerCopy := *player
		copy.Players[i] = &playerCopy
	}
	if table.LastResult != nil {
		result := *table.LastResult
		result.Selections = append([]Selection(nil), table.LastResult.Selections...)
		copy.LastResult = &result
	}
	return &copy
}
