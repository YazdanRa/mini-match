package game

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	maxPlayerNameLength = 40
	maxTableNameLength  = 80
)

var (
	ErrAlreadyExists  = errors.New("already exists")
	ErrAlreadyLocked  = errors.New("pick already locked")
	ErrForbidden      = errors.New("only the host can start or reveal the round")
	ErrInvalid        = errors.New("invalid input")
	ErrNotFound       = errors.New("not found")
	ErrNotReady       = errors.New("every player must lock a pick")
	ErrRoundActive    = errors.New("a round is already active")
	ErrRoundExhausted = errors.New("round sequence exhausted")
	ErrRoundMismatch  = errors.New("round number does not match")
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
	CurrentRound       *Round
	LastResult         *Result
	WinnerLifetimeWins uint64
	Version            uint64
	EventSequence      uint64
}

type Player struct {
	ID                string
	GameCenterID      string
	Name              string
	Avatar            string
	Locked            bool
	Pick              uint64
	PresenceExpiresAt time.Time
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
	PlayerID    string
	DisplayName string
	Pick        uint64
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
	if player := t.player(playerID); player != nil {
		if player.Name != name || player.Avatar != avatar {
			player.Name = name
			player.Avatar = avatar
			t.changed()
		}
		return nil
	}
	t.Players = append(t.Players, &Player{ID: playerID, Name: name, Avatar: avatar})
	if len(t.Players) == 1 {
		t.HostID = playerID
		t.CurrentRound = nil
		t.LastResult = nil
	}
	if t.CurrentRound != nil && t.CurrentRound.Phase == RoundReady {
		t.CurrentRound.Phase = RoundOpen
	}
	t.changed()
	return nil
}

func (t *Table) Leave(playerID string) error {
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
		if t.CurrentRound != nil && len(t.Players) < 2 {
			t.CurrentRound = nil
			for _, remaining := range t.Players {
				remaining.Locked = false
				remaining.Pick = 0
			}
		} else if t.CurrentRound != nil {
			t.CurrentRound.Phase = RoundReady
			for _, remaining := range t.Players {
				if !remaining.Locked {
					t.CurrentRound.Phase = RoundOpen
					break
				}
			}
		}
		if len(t.Players) == 0 {
			t.CurrentRound = nil
			t.LastResult = nil
			t.WinnerLifetimeWins = 0
		}
		t.changed()
		return nil
	}
	return ErrNotFound
}

func (t *Table) PresenceUpdateNeeded(playerID string, now time.Time, duration time.Duration) bool {
	player := t.player(playerID)
	if player == nil || player.PresenceExpiresAt.IsZero() ||
		!player.PresenceExpiresAt.After(now.Add(duration/2)) {
		return player != nil
	}
	for _, current := range t.Players {
		if current.PresenceExpiresAt.IsZero() || !current.PresenceExpiresAt.After(now) {
			return true
		}
	}
	return false
}

func (t *Table) RefreshPresence(playerID string, now time.Time, duration time.Duration) error {
	if duration <= 0 || t.player(playerID) == nil {
		return ErrNotFound
	}
	expiresAt := now.Add(duration)
	for _, player := range t.Players {
		if player.ID == playerID || player.PresenceExpiresAt.IsZero() {
			player.PresenceExpiresAt = expiresAt
		}
	}
	for index := len(t.Players) - 1; index >= 0; index-- {
		player := t.Players[index]
		if player.ID != playerID && !player.PresenceExpiresAt.After(now) {
			if err := t.Leave(player.ID); err != nil {
				return err
			}
		}
	}
	return nil
}

func (t *Table) LockPick(playerID string, pick uint64, roundNumber uint32) error {
	player := t.player(playerID)
	if player == nil {
		return ErrNotFound
	}
	if t.CurrentRound == nil {
		return ErrNotReady
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

func (t *Table) BeginRound(actorID string) error {
	if len(t.Players) < 2 {
		return ErrNotReady
	}
	if actorID != t.HostID {
		return ErrForbidden
	}
	if t.CurrentRound != nil {
		return ErrRoundActive
	}
	expectedRound := uint32(1)
	if t.LastResult != nil {
		if t.LastResult.RoundNumber == math.MaxUint32 {
			return ErrRoundExhausted
		}
		expectedRound = t.LastResult.RoundNumber + 1
	}
	t.CurrentRound = &Round{Number: expectedRound, Phase: RoundOpen}
	t.changed()
	return nil
}

func (t *Table) RevealRound(actorID string, roundNumber uint32) error {
	if len(t.Players) < 2 {
		return ErrNotReady
	}
	if actorID != t.HostID {
		return ErrForbidden
	}
	if t.CurrentRound == nil {
		return ErrNotReady
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
		result.Selections = append(result.Selections, Selection{
			PlayerID:    player.ID,
			DisplayName: player.Name,
			Pick:        player.Pick,
		})
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
				break
			}
		}
	}
	t.LastResult = result
	t.WinnerLifetimeWins = 0
	for _, player := range t.Players {
		player.Locked = false
		player.Pick = 0
	}
	t.CurrentRound = nil
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
	if gameCenterID != "" {
		for _, existing := range t.Players {
			if existing.ID != playerID && existing.GameCenterID == gameCenterID {
				return fmt.Errorf("%w: Game Center identity", ErrAlreadyExists)
			}
		}
	}
	player.GameCenterID = gameCenterID
	return nil
}

func (t *Table) DeletePlayerProfile(playerID, replacementID string) error {
	playerIsPresent := t.player(playerID) != nil
	resultChanged := false
	if t.LastResult != nil {
		if t.LastResult.WinnerID == playerID {
			t.LastResult.WinnerID = replacementID
			resultChanged = true
		}
		for index := range t.LastResult.Selections {
			if t.LastResult.Selections[index].PlayerID == playerID {
				t.LastResult.Selections[index].PlayerID = replacementID
				t.LastResult.Selections[index].DisplayName = ""
				resultChanged = true
			}
		}
	}
	if playerIsPresent {
		return t.Leave(playerID)
	}
	if !resultChanged {
		return ErrNotFound
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
	if value == "" || utf8.RuneCountInString(value) > maxLength {
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
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		tables: make(map[string]*Table),
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
	r.tables[id] = next
	return clone(next), nil
}

func (r *MemoryRepository) DeleteProfile(_ context.Context, playerID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, table := range r.tables {
		next := clone(table)
		if err := next.DeletePlayerProfile(playerID, "deleted:"+id); err == nil {
			r.tables[id] = next
		}
	}
	return nil
}

func clone(table *Table) *Table {
	copy := *table
	if table.CurrentRound != nil {
		round := *table.CurrentRound
		copy.CurrentRound = &round
	}
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
