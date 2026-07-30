package game

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
)

const WinningScore = 5

const (
	maxPlayerNameLength = 40
	maxTableNameLength  = 80
)

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
	ID                 string
	Name               string
	JoinCode           string
	HostID             string
	Players            []*Player
	CurrentRound       Round
	LastResult         *Result
	WinnerID           string
	WinnerLifetimeWins uint64
	Version            uint64
	EventSequence      uint64
}

type Player struct {
	ID           string
	GameCenterID string
	Name         string
	Avatar       string
	Score        uint32
	Locked       bool
	Pick         uint64
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

func NewTable(id, name, joinCode, hostID, hostName, hostAvatar string) (*Table, error) {
	name, err := normalizedText(name, maxTableNameLength)
	if err != nil {
		return nil, err
	}
	hostName, err = normalizedText(hostName, maxPlayerNameLength)
	if err != nil || blank(id) || blank(joinCode) || blank(hostID) {
		return nil, ErrInvalid
	}
	avatar, err := normalizedAvatar(hostAvatar)
	if err != nil {
		return nil, err
	}
	return &Table{
		ID:            id,
		Name:          name,
		JoinCode:      joinCode,
		HostID:        hostID,
		Players:       []*Player{{ID: hostID, Name: hostName, Avatar: avatar}},
		CurrentRound:  Round{Number: 1, Phase: RoundOpen},
		Version:       1,
		EventSequence: 1,
	}, nil
}

func (t *Table) Join(playerID, name, avatarID string) error {
	name, err := normalizedText(name, maxPlayerNameLength)
	if err != nil || blank(playerID) {
		return ErrInvalid
	}
	avatar, err := normalizedAvatar(avatarID)
	if err != nil {
		return err
	}
	if t.WinnerID != "" {
		return ErrFinished
	}
	if t.player(playerID) != nil {
		return ErrAlreadyExists
	}
	t.Players = append(t.Players, &Player{ID: playerID, Name: name, Avatar: avatar})
	if len(t.Players) == 1 {
		t.HostID = playerID
		t.CurrentRound = Round{Number: 1, Phase: RoundOpen}
		t.LastResult = nil
		t.WinnerID = ""
	}
	if t.CurrentRound.Phase == RoundReady {
		t.CurrentRound.Phase = RoundOpen
	}
	t.changed()
	return nil
}

func (t *Table) Leave(playerID string) error {
	if t.WinnerID != "" {
		return ErrFinished
	}
	for index, player := range t.Players {
		if player.ID != playerID {
			continue
		}
		t.Players = append(t.Players[:index], t.Players[index+1:]...)
		if playerID == t.HostID {
			t.HostID = ""
			if len(t.Players) != 0 {
				t.HostID = t.Players[0].ID
			}
		}
		t.CurrentRound.Phase = RoundReady
		for _, remaining := range t.Players {
			if !remaining.Locked {
				t.CurrentRound.Phase = RoundOpen
				break
			}
		}
		if len(t.Players) == 0 {
			t.CurrentRound = Round{Number: 1, Phase: RoundOpen}
			t.LastResult = nil
		}
		t.changed()
		return nil
	}
	return ErrNotFound
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

func (t *Table) SetGameCenterID(playerID, gameCenterID string) error {
	player := t.player(playerID)
	if player == nil {
		return ErrNotFound
	}
	player.GameCenterID = gameCenterID
	return nil
}

func (t *Table) DeletePlayerProfile(playerID, replacementID string) error {
	if t.WinnerID == "" {
		return t.Leave(playerID)
	}
	player := t.player(playerID)
	if player == nil {
		return ErrNotFound
	}
	player.ID = replacementID
	player.GameCenterID = ""
	player.Name = "Deleted Player"
	player.Avatar = "spark"
	if t.HostID == playerID {
		t.HostID = replacementID
	}
	if t.WinnerID == playerID {
		t.WinnerID = replacementID
	}
	if t.LastResult != nil {
		if t.LastResult.WinnerID == playerID {
			t.LastResult.WinnerID = replacementID
		}
		for index := range t.LastResult.Selections {
			if t.LastResult.Selections[index].PlayerID == playerID {
				t.LastResult.Selections[index].PlayerID = replacementID
			}
		}
	}
	t.changed()
	return nil
}

func (t *Table) changed() {
	t.Version++
	t.EventSequence++
}

func blank(value string) bool {
	return strings.TrimSpace(value) == ""
}

func normalizedText(value string, maxLength int) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || len(value) > maxLength {
		return "", ErrInvalid
	}
	return value, nil
}

func normalizedAvatar(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "spark", nil
	}
	switch value {
	case "spark", "fox", "owl", "cat", "dog", "frog":
		return value, nil
	default:
		return "", ErrInvalid
	}
}

type Repository interface {
	Create(context.Context, *Table) error
	Get(context.Context, string) (*Table, error)
	GetByJoinCode(context.Context, string) (*Table, error)
	Update(context.Context, string, func(*Table) error) (*Table, error)
	DeleteProfile(context.Context, string) error
}

type MemoryRepository struct {
	mu     sync.Mutex
	tables map[string]*Table
	wins   map[string]uint64
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		tables: make(map[string]*Table),
		wins:   make(map[string]uint64),
	}
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
	if table.WinnerID == "" && next.WinnerID != "" {
		if winner := next.player(next.WinnerID); winner != nil && winner.GameCenterID != "" {
			r.wins[winner.GameCenterID]++
			next.WinnerLifetimeWins = r.wins[winner.GameCenterID]
		}
	}
	r.tables[id] = next
	return clone(next), nil
}

func (r *MemoryRepository) DeleteProfile(_ context.Context, playerID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, table := range r.tables {
		next := clone(table)
		for _, player := range next.Players {
			if player.ID == playerID && player.GameCenterID != "" {
				delete(r.wins, player.GameCenterID)
			}
		}
		if err := next.DeletePlayerProfile(playerID, "deleted:"+id); err == nil {
			r.tables[id] = next
		}
	}
	return nil
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
