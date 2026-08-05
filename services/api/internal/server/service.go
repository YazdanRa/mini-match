package server

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"math/big"
	"strings"
	"time"

	"connectrpc.com/connect"
	minimatchv1 "github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1"
	"github.com/YazdanRa/mini-match/services/api/internal/authn"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

type Service struct {
	tables game.Repository
	now    func() time.Time
}

func New(tables game.Repository) *Service {
	return &Service{tables: tables, now: time.Now}
}

const playerPresenceDuration = 2 * time.Minute

func (s *Service) CreateTable(ctx context.Context, request *connect.Request[minimatchv1.CreateTableRequest]) (*connect.Response[minimatchv1.CreateTableResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	gameCenterID, err := verifyGameCenterIdentity(ctx, request.Msg.GetGameCenterIdentity())
	if err != nil {
		return nil, connect.NewError(connect.CodeUnauthenticated, err)
	}
	requestedJoinCode := strings.ToUpper(strings.TrimSpace(request.Msg.GetJoinCode()))
	if requestedJoinCode != "" && !validPartyCode(requestedJoinCode) {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("invalid join code"))
	}
	for range 3 {
		tableID, err := token(16)
		if err != nil {
			return nil, rpcError(err)
		}
		joinCode := requestedJoinCode
		if joinCode == "" {
			joinCode, err = partyCode()
			if err != nil {
				return nil, rpcError(err)
			}
		}
		table, err := game.NewTable(
			tableID,
			request.Msg.GetName(),
			joinCode,
			actor,
			request.Msg.GetHostDisplayName(),
			request.Msg.GetHostAvatar(),
		)
		if err != nil {
			return nil, rpcError(err)
		}
		if err := table.SetGameCenterID(actor, gameCenterID); err != nil {
			return nil, rpcError(err)
		}
		if err := table.RefreshPresence(actor, s.now(), playerPresenceDuration); err != nil {
			return nil, rpcError(err)
		}
		if err := s.tables.Create(ctx, table); err != nil {
			if errors.Is(err, game.ErrAlreadyExists) {
				if requestedJoinCode != "" {
					return nil, connect.NewError(connect.CodeAlreadyExists, err)
				}
				continue
			}
			return nil, rpcError(err)
		}
		return connect.NewResponse(&minimatchv1.CreateTableResponse{
			Table:    toProto(table, actor),
			PlayerId: actor,
		}), nil
	}
	return nil, connect.NewError(connect.CodeResourceExhausted, errors.New("could not allocate table identity"))
}

func (s *Service) JoinTable(ctx context.Context, request *connect.Request[minimatchv1.JoinTableRequest]) (*connect.Response[minimatchv1.JoinTableResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	gameCenterID, err := verifyGameCenterIdentity(ctx, request.Msg.GetGameCenterIdentity())
	if err != nil {
		return nil, connect.NewError(connect.CodeUnauthenticated, err)
	}
	table, err := s.tables.GetByJoinCode(ctx, strings.ToUpper(strings.TrimSpace(request.Msg.GetJoinCode())))
	if err != nil {
		return nil, rpcError(err)
	}
	table, err = s.tables.Update(ctx, table.ID, func(table *game.Table) error {
		return s.joinTable(
			table,
			actor,
			request.Msg.GetDisplayName(),
			request.Msg.GetAvatar(),
			gameCenterID,
		)
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.JoinTableResponse{
		Table:    toProto(table, actor),
		PlayerId: actor,
	}), nil
}

func (s *Service) joinTable(
	table *game.Table,
	actor, displayName, avatar, gameCenterID string,
) error {
	if err := table.Join(actor, displayName, avatar); err != nil {
		return err
	}
	if err := table.RefreshPresence(actor, s.now(), playerPresenceDuration); err != nil {
		return err
	}
	return table.SetGameCenterID(actor, gameCenterID)
}

func (s *Service) LeaveTable(ctx context.Context, request *connect.Request[minimatchv1.LeaveTableRequest]) (*connect.Response[minimatchv1.LeaveTableResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if request.Msg.GetPlayerId() != "" && request.Msg.GetPlayerId() != actor {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("player ID does not match authenticated user"))
	}
	table, err := s.tables.Update(ctx, request.Msg.GetTableId(), func(table *game.Table) error {
		return table.Leave(actor)
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.LeaveTableResponse{Table: toProto(table, actor)}), nil
}

func (s *Service) LockPick(ctx context.Context, request *connect.Request[minimatchv1.LockPickRequest]) (*connect.Response[minimatchv1.LockPickResponse], error) {
	if request.Msg.GetPick() == nil {
		return nil, rpcError(game.ErrInvalid)
	}
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if request.Msg.GetPlayerId() != "" && request.Msg.GetPlayerId() != actor {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("player ID does not match authenticated user"))
	}
	table, err := s.updateActiveTable(ctx, request.Msg.GetTableId(), actor, func(table *game.Table) error {
		return table.LockPick(actor, request.Msg.GetPick().GetValue(), request.Msg.GetRoundNumber())
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.LockPickResponse{Table: toProto(table, actor)}), nil
}

func (s *Service) StartRound(ctx context.Context, request *connect.Request[minimatchv1.StartRoundRequest]) (*connect.Response[minimatchv1.StartRoundResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if request.Msg.GetHostPlayerId() != "" && request.Msg.GetHostPlayerId() != actor {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("host player ID does not match authenticated user"))
	}
	table, err := s.revealRound(ctx, request.Msg.GetTableId(), actor, request.Msg.GetRoundNumber())
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.StartRoundResponse{Table: toProto(table, actor)}), nil
}

func (s *Service) BeginRound(ctx context.Context, request *connect.Request[minimatchv1.BeginRoundRequest]) (*connect.Response[minimatchv1.BeginRoundResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if request.Msg.GetHostPlayerId() != "" && request.Msg.GetHostPlayerId() != actor {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("host player ID does not match authenticated user"))
	}
	table, err := s.updateActiveTable(ctx, request.Msg.GetTableId(), actor, func(table *game.Table) error {
		return table.BeginRound(actor)
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.BeginRoundResponse{Table: toProto(table, actor)}), nil
}

func (s *Service) RevealRound(ctx context.Context, request *connect.Request[minimatchv1.RevealRoundRequest]) (*connect.Response[minimatchv1.RevealRoundResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if request.Msg.GetHostPlayerId() != "" && request.Msg.GetHostPlayerId() != actor {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("host player ID does not match authenticated user"))
	}
	table, err := s.revealRound(ctx, request.Msg.GetTableId(), actor, request.Msg.GetRoundNumber())
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.RevealRoundResponse{Table: toProto(table, actor)}), nil
}

func (s *Service) GetTable(ctx context.Context, request *connect.Request[minimatchv1.GetTableRequest]) (*connect.Response[minimatchv1.GetTableResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	table, err := s.tables.Get(ctx, request.Msg.GetTableId())
	if err != nil {
		return nil, rpcError(err)
	}
	if !table.HasPlayer(actor) {
		return nil, connect.NewError(connect.CodePermissionDenied, game.ErrForbidden)
	}
	if table.PresenceUpdateNeeded(actor, s.now(), playerPresenceDuration) {
		table, err = s.tables.Update(ctx, table.ID, func(table *game.Table) error {
			return table.RefreshPresence(actor, s.now(), playerPresenceDuration)
		})
		if err != nil {
			return nil, rpcError(err)
		}
	}
	return connect.NewResponse(&minimatchv1.GetTableResponse{Table: toProto(table, actor)}), nil
}

func (s *Service) updateActiveTable(
	ctx context.Context,
	tableID string,
	actor string,
	update func(*game.Table) error,
) (*game.Table, error) {
	return s.tables.Update(ctx, tableID, func(table *game.Table) error {
		if err := table.RefreshPresence(actor, s.now(), playerPresenceDuration); err != nil {
			return err
		}
		return update(table)
	})
}

func (s *Service) revealRound(
	ctx context.Context,
	tableID string,
	actor string,
	roundNumber uint32,
) (*game.Table, error) {
	return s.tables.RevealRound(ctx, tableID, func(table *game.Table) error {
		if err := table.RefreshPresence(actor, s.now(), playerPresenceDuration); err != nil {
			return err
		}
		return table.RevealRound(actor, roundNumber)
	})
}

func (s *Service) DeleteProfile(
	ctx context.Context,
	_ *connect.Request[minimatchv1.DeleteProfileRequest],
) (*connect.Response[minimatchv1.DeleteProfileResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.tables.DeleteProfile(ctx, actor); err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.DeleteProfileResponse{}), nil
}

func actorID(ctx context.Context) (string, error) {
	actor, ok := authn.ActorID(ctx)
	if !ok {
		return "", connect.NewError(connect.CodeUnauthenticated, errors.New("missing authenticated user"))
	}
	return actor, nil
}

func token(bytes int) (string, error) {
	value := make([]byte, bytes)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return hex.EncodeToString(value), nil
}

func partyCode() (string, error) {
	const alphabet = "23456789CFGHJMPQRVWX"
	code := make([]byte, 9)
	for index := range code {
		if index == 4 {
			code[index] = '-'
			continue
		}
		value, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", err
		}
		code[index] = alphabet[value.Int64()]
	}
	return string(code), nil
}

func validPartyCode(code string) bool {
	parts := strings.Split(code, "-")
	if len(parts) != 2 || len(parts[0]) != len(parts[1]) ||
		len(parts[0]) < 2 || len(parts[0]) > 6 {
		return false
	}
	allDigits := true
	for _, value := range parts[0] + parts[1] {
		if value < '0' || value > '9' {
			allDigits = false
			break
		}
	}
	if allDigits {
		return true
	}
	for _, value := range parts[0] + parts[1] {
		if !strings.ContainsRune("23456789CFGHJMPQRVWX", value) {
			return false
		}
	}
	return true
}

func toProto(table *game.Table, actor string) *minimatchv1.Table {
	response := &minimatchv1.Table{
		Id:            table.ID,
		Name:          table.Name,
		JoinCode:      table.JoinCode,
		HostPlayerId:  table.HostID,
		State:         minimatchv1.TableState_TABLE_STATE_ACTIVE,
		StateVersion:  table.Version,
		EventSequence: table.EventSequence,
		Players:       make([]*minimatchv1.Player, 0, len(table.Players)),
	}
	for _, player := range table.Players {
		response.Players = append(response.Players, &minimatchv1.Player{
			Id:          player.ID,
			DisplayName: player.Name,
			Avatar:      player.Avatar,
			Locked:      player.Locked,
		})
	}
	if table.CurrentRound != nil {
		response.CurrentRound = &minimatchv1.Round{Number: table.CurrentRound.Number}
		switch table.CurrentRound.Phase {
		case game.RoundOpen:
			response.CurrentRound.Phase = minimatchv1.RoundPhase_ROUND_PHASE_ACCEPTING_PICKS
		case game.RoundReady:
			response.CurrentRound.Phase = minimatchv1.RoundPhase_ROUND_PHASE_READY_TO_REVEAL
		}
	}
	if table.LastResult != nil {
		response.LastResult = &minimatchv1.RoundResult{
			RoundNumber:          table.LastResult.RoundNumber,
			Selections:           make([]*minimatchv1.Selection, 0, len(table.LastResult.Selections)),
			WinnerAchievementIds: winnerAchievementIDs(table.LastResult),
		}
		if table.LastResult.WinnerID != "" {
			winner := table.LastResult.WinnerID
			response.LastResult.WinnerPlayerId = &winner
		}
		if table.LastResult.WinnerID == actor && table.LastResult.WinnerTotalWins > 0 {
			score := table.LastResult.WinnerTotalWins
			response.LastResult.LocalPlayerLeaderboardScore = &score
		}
		for _, selection := range table.LastResult.Selections {
			response.LastResult.Selections = append(response.LastResult.Selections, &minimatchv1.Selection{
				PlayerId:    selection.PlayerID,
				Pick:        &minimatchv1.Pick{Value: selection.Pick},
				DisplayName: selection.DisplayName,
			})
		}
	}
	return response
}

func winnerAchievementIDs(result *game.Result) []string {
	const prefix = "com.yazdanra.minimatch.achievement."
	ids := make([]string, 0, 5)
	if result.WinnerBestWinStreak >= 2 {
		ids = append(ids, prefix+"twoWinStreak")
	}
	if result.WinnerBestWinStreak >= 4 {
		ids = append(ids, prefix+"fourWinStreak")
	}
	if result.WinnerTotalWins >= 16 {
		ids = append(ids, prefix+"sixteenRoundWins")
	}
	if result.WinnerTotalWins >= 32 {
		ids = append(ids, prefix+"thirtyTwoRoundWins")
	}
	if result.WinnerTotalWins >= 64 {
		ids = append(ids, prefix+"sixtyFourRoundWins")
	}
	return ids
}

func rpcError(err error) error {
	code := connect.CodeInternal
	switch {
	case errors.Is(err, game.ErrInvalid):
		code = connect.CodeInvalidArgument
	case errors.Is(err, game.ErrNotFound):
		code = connect.CodeNotFound
	case errors.Is(err, game.ErrAlreadyExists):
		code = connect.CodeAlreadyExists
	case errors.Is(err, game.ErrForbidden):
		code = connect.CodePermissionDenied
	case errors.Is(err, game.ErrAlreadyLocked),
		errors.Is(err, game.ErrNotReady),
		errors.Is(err, game.ErrRoundActive),
		errors.Is(err, game.ErrRoundMismatch):
		code = connect.CodeFailedPrecondition
	case errors.Is(err, game.ErrRoundExhausted), errors.Is(err, game.ErrStatsExhausted):
		code = connect.CodeResourceExhausted
	}
	return connect.NewError(code, err)
}
