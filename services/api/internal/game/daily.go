package game

import (
	"context"
	"crypto/sha256"
	"fmt"
	"iter"
	"math"
	"sort"
	"time"
)

const DailyDateLayout = "2006-01-02"

type DailyRoundStatus string

const (
	DailyRoundOpen         DailyRoundStatus = "open"
	DailyRoundCalculating  DailyRoundStatus = "calculating"
	DailyRoundEmpty        DailyRoundStatus = "empty"
	DailyRoundInsufficient DailyRoundStatus = "insufficient"
	DailyRoundNoUnique     DailyRoundStatus = "no_unique"
	DailyRoundWinner       DailyRoundStatus = "winner"
)

type DailyGlobalTable struct {
	ServerTime time.Time
	Today      DailyRoundView
	Yesterday  DailyRoundView
	TotalWins  uint64
}

type DailyRoundView struct {
	Date         string
	ClosesAt     time.Time
	Status       DailyRoundStatus
	EntrantCount uint64
	WinningPick  uint64
	Pick         uint64
	Won          bool
}

type DailyEntry struct {
	PlayerHash string
	Pick       uint64
}

type DailyResolution struct {
	Status       DailyRoundStatus
	EntrantCount uint64
	WinningPick  uint64
	WinnerHash   string
}

func DailyDate(now time.Time) string {
	return now.UTC().Format(DailyDateLayout)
}

func DailyClosesAt(date string) (time.Time, error) {
	start, err := time.Parse(DailyDateLayout, date)
	if err != nil || start.Format(DailyDateLayout) != date {
		return time.Time{}, ErrInvalid
	}
	return start.AddDate(0, 0, 1), nil
}

func ResolveDailyRound(entries []DailyEntry) (DailyResolution, error) {
	entries = append([]DailyEntry(nil), entries...)
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Pick == entries[j].Pick {
			return entries[i].PlayerHash < entries[j].PlayerHash
		}
		return entries[i].Pick < entries[j].Pick
	})
	return ResolveSortedDailyRound(func(yield func(DailyEntry, error) bool) {
		for _, entry := range entries {
			if !yield(entry, nil) {
				return
			}
		}
	})
}

func ResolveSortedDailyRound(entries iter.Seq2[DailyEntry, error]) (DailyResolution, error) {
	var result DailyResolution
	var current DailyEntry
	var currentCount uint64
	var haveCurrent bool
	for entry, err := range entries {
		if err != nil {
			return DailyResolution{}, err
		}
		if entry.Pick == 0 || blank(entry.PlayerHash) || (haveCurrent && entry.Pick < current.Pick) {
			return DailyResolution{}, ErrInvalid
		}
		if result.EntrantCount == ^uint64(0) {
			return DailyResolution{}, ErrStatsExhausted
		}
		result.EntrantCount++
		if haveCurrent && entry.Pick != current.Pick {
			if currentCount == 1 && result.WinnerHash == "" {
				result.WinningPick = current.Pick
				result.WinnerHash = current.PlayerHash
			}
			currentCount = 0
		}
		current = entry
		currentCount++
		haveCurrent = true
	}
	if currentCount == 1 && result.WinnerHash == "" {
		result.WinningPick = current.Pick
		result.WinnerHash = current.PlayerHash
	}
	switch result.EntrantCount {
	case 0:
		result.Status = DailyRoundEmpty
	case 1:
		result.Status = DailyRoundInsufficient
		result.WinningPick = 0
		result.WinnerHash = ""
	default:
		if result.WinnerHash == "" {
			result.Status = DailyRoundNoUnique
		} else {
			result.Status = DailyRoundWinner
		}
	}
	return result, nil
}

type dailyRound struct {
	Date             string
	ClosesAt         time.Time
	Status           DailyRoundStatus
	EntrantCount     uint64
	WinningPick      uint64
	CleanupScheduled bool
	Entries          map[string]DailyEntry
	Claims           map[string]string
}

func newDailyRound(date string) (*dailyRound, error) {
	closesAt, err := DailyClosesAt(date)
	if err != nil {
		return nil, err
	}
	return &dailyRound{
		Date:     date,
		ClosesAt: closesAt,
		Status:   DailyRoundOpen,
		Entries:  make(map[string]DailyEntry),
		Claims:   make(map[string]string),
	}, nil
}

func (r *dailyRound) view(playerHash string) DailyRoundView {
	view := DailyRoundView{
		Date:         r.Date,
		ClosesAt:     r.ClosesAt,
		Status:       r.Status,
		EntrantCount: r.EntrantCount,
		WinningPick:  r.WinningPick,
	}
	if entry, ok := r.Entries[playerHash]; ok {
		view.Pick = entry.Pick
		view.Won = r.Status == DailyRoundWinner && entry.Pick == r.WinningPick
	}
	return view
}

func dailyIdentityHash(kind, value string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte("mini-match:daily:"+kind+"\x00"+value)))
}

func (r *MemoryRepository) GetDailyGlobalTable(
	_ context.Context,
	actorID string,
	gameCenterID string,
	now time.Time,
) (*DailyGlobalTable, error) {
	if blank(actorID) || blank(gameCenterID) {
		return nil, ErrInvalid
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.dailyTable(actorID, gameCenterID, now.UTC())
}

func (r *MemoryRepository) LockDailyGlobalPick(
	_ context.Context,
	actorID string,
	gameCenterID string,
	roundDate string,
	pick uint64,
	now time.Time,
) (*DailyGlobalTable, error) {
	if blank(actorID) || blank(gameCenterID) || pick == 0 {
		return nil, ErrInvalid
	}
	now = now.UTC()
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, err := DailyClosesAt(roundDate); err != nil {
		return nil, err
	}
	accountHash := dailyIdentityHash("account", actorID)
	playerHash := dailyIdentityHash("player", gameCenterID)
	if round := r.dailyRounds[roundDate]; round != nil {
		claimedPlayer, hasClaim := round.Claims[accountHash]
		entry, hasEntry := round.Entries[playerHash]
		if hasClaim || hasEntry {
			if hasClaim && hasEntry && claimedPlayer == playerHash && entry.Pick == pick {
				return r.dailyTable(actorID, gameCenterID, now)
			}
			return nil, ErrAlreadyLocked
		}
	}
	if roundDate != DailyDate(now) {
		return nil, ErrRoundMismatch
	}
	round, err := r.memoryDailyRound(roundDate)
	if err != nil {
		return nil, err
	}
	if !now.Before(round.ClosesAt) || round.Status != DailyRoundOpen {
		return nil, ErrRoundMismatch
	}
	round.Claims[accountHash] = playerHash
	round.Entries[playerHash] = DailyEntry{PlayerHash: playerHash, Pick: pick}
	return r.dailyTable(actorID, gameCenterID, now)
}

func (r *MemoryRepository) dailyTable(actorID, gameCenterID string, now time.Time) (*DailyGlobalTable, error) {
	for _, round := range r.dailyRounds {
		if !now.Before(round.ClosesAt) &&
			(round.Status == DailyRoundOpen || round.Status == DailyRoundCalculating) {
			if err := r.finalizeDailyRound(round); err != nil {
				return nil, err
			}
		}
	}
	todayDate := DailyDate(now)
	today, err := r.memoryDailyRound(todayDate)
	if err != nil {
		return nil, err
	}
	yesterdayDate := DailyDate(now.AddDate(0, 0, -1))
	yesterday, err := r.memoryDailyRound(yesterdayDate)
	if err != nil {
		return nil, err
	}
	if err := r.finalizeDailyRound(yesterday); err != nil {
		return nil, err
	}
	playerHash := dailyIdentityHash("player", gameCenterID)
	return &DailyGlobalTable{
		ServerTime: now,
		Today:      today.view(playerHash),
		Yesterday:  yesterday.view(playerHash),
		TotalWins:  r.dailyStats[playerHash],
	}, nil
}

func (r *MemoryRepository) memoryDailyRound(date string) (*dailyRound, error) {
	if round := r.dailyRounds[date]; round != nil {
		return round, nil
	}
	round, err := newDailyRound(date)
	if err != nil {
		return nil, err
	}
	r.dailyRounds[date] = round
	return round, nil
}

func (r *MemoryRepository) finalizeDailyRound(round *dailyRound) error {
	if round.Status != DailyRoundOpen && round.Status != DailyRoundCalculating {
		return nil
	}
	round.Status = DailyRoundCalculating
	entries := make([]DailyEntry, 0, len(round.Entries))
	for _, entry := range round.Entries {
		entries = append(entries, entry)
	}
	result, err := ResolveDailyRound(entries)
	if err != nil {
		return err
	}
	if result.Status == DailyRoundWinner {
		if r.dailyStats[result.WinnerHash] == math.MaxUint64 {
			return ErrStatsExhausted
		}
		r.dailyStats[result.WinnerHash]++
	}
	round.Status = result.Status
	round.EntrantCount = result.EntrantCount
	round.WinningPick = result.WinningPick
	round.CleanupScheduled = true
	return nil
}
