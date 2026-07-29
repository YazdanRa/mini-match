package server

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"

	"connectrpc.com/connect"
	minimatchv1 "github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1"
	"github.com/YazdanRa/mini-match/services/api/internal/authn"
	"github.com/YazdanRa/mini-match/services/api/internal/game"
)

type Service struct {
	tables game.Repository
}

func New(tables game.Repository) *Service {
	return &Service{tables: tables}
}

func (s *Service) CreateTable(ctx context.Context, request *connect.Request[minimatchv1.CreateTableRequest]) (*connect.Response[minimatchv1.CreateTableResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	for range 3 {
		tableID, err := token(16)
		if err != nil {
			return nil, rpcError(err)
		}
		joinCode, err := token(4)
		if err != nil {
			return nil, rpcError(err)
		}
		table, err := game.NewTable(
			tableID,
			request.Msg.GetName(),
			strings.ToUpper(joinCode),
			actor,
			request.Msg.GetHostDisplayName(),
			request.Msg.GetHostAvatar(),
		)
		if err != nil {
			return nil, rpcError(err)
		}
		if err := s.tables.Create(ctx, table); err != nil {
			if errors.Is(err, game.ErrAlreadyExists) {
				continue
			}
			return nil, rpcError(err)
		}
		return connect.NewResponse(&minimatchv1.CreateTableResponse{
			Table:    toProto(table),
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
	table, err := s.tables.GetByJoinCode(ctx, strings.ToUpper(strings.TrimSpace(request.Msg.GetJoinCode())))
	if err != nil {
		return nil, rpcError(err)
	}
	table, err = s.tables.Update(ctx, table.ID, func(table *game.Table) error {
		return table.Join(actor, request.Msg.GetDisplayName(), request.Msg.GetAvatar())
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.JoinTableResponse{
		Table:    toProto(table),
		PlayerId: actor,
	}), nil
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
	return connect.NewResponse(&minimatchv1.LeaveTableResponse{Table: toProto(table)}), nil
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
	table, err := s.tables.Update(ctx, request.Msg.GetTableId(), func(table *game.Table) error {
		return table.LockPick(actor, request.Msg.GetPick().GetValue(), request.Msg.GetRoundNumber())
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.LockPickResponse{Table: toProto(table)}), nil
}

func (s *Service) StartRound(ctx context.Context, request *connect.Request[minimatchv1.StartRoundRequest]) (*connect.Response[minimatchv1.StartRoundResponse], error) {
	actor, err := actorID(ctx)
	if err != nil {
		return nil, err
	}
	if request.Msg.GetHostPlayerId() != "" && request.Msg.GetHostPlayerId() != actor {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("host player ID does not match authenticated user"))
	}
	table, err := s.tables.Update(ctx, request.Msg.GetTableId(), func(table *game.Table) error {
		return table.StartRound(actor, request.Msg.GetRoundNumber())
	})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&minimatchv1.StartRoundResponse{Table: toProto(table)}), nil
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
	return connect.NewResponse(&minimatchv1.GetTableResponse{Table: toProto(table)}), nil
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

func toProto(table *game.Table) *minimatchv1.Table {
	state := minimatchv1.TableState_TABLE_STATE_ACTIVE
	var winnerID *string
	if table.WinnerID != "" {
		state = minimatchv1.TableState_TABLE_STATE_FINISHED
		winner := table.WinnerID
		winnerID = &winner
	}
	response := &minimatchv1.Table{
		Id:             table.ID,
		Name:           table.Name,
		JoinCode:       table.JoinCode,
		HostPlayerId:   table.HostID,
		State:          state,
		WinsToFinish:   game.WinningScore,
		StateVersion:   table.Version,
		EventSequence:  table.EventSequence,
		WinnerPlayerId: winnerID,
		Players:        make([]*minimatchv1.Player, 0, len(table.Players)),
	}
	for _, player := range table.Players {
		response.Players = append(response.Players, &minimatchv1.Player{
			Id:          player.ID,
			DisplayName: player.Name,
			Avatar:      player.Avatar,
			Wins:        player.Score,
			Locked:      player.Locked,
		})
	}
	if table.WinnerID == "" {
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
			RoundNumber: table.LastResult.RoundNumber,
			Selections:  make([]*minimatchv1.Selection, 0, len(table.LastResult.Selections)),
		}
		if table.LastResult.WinnerID != "" {
			winner := table.LastResult.WinnerID
			response.LastResult.WinnerPlayerId = &winner
		}
		for _, selection := range table.LastResult.Selections {
			response.LastResult.Selections = append(response.LastResult.Selections, &minimatchv1.Selection{
				PlayerId: selection.PlayerID,
				Pick:     &minimatchv1.Pick{Value: selection.Pick},
			})
		}
	}
	return response
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
		errors.Is(err, game.ErrFinished),
		errors.Is(err, game.ErrNotReady),
		errors.Is(err, game.ErrRoundMismatch):
		code = connect.CodeFailedPrecondition
	}
	return connect.NewError(code, err)
}
