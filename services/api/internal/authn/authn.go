package authn

import (
	"context"
	"errors"
	"strings"

	"connectrpc.com/connect"
	"firebase.google.com/go/v4/appcheck"
	"firebase.google.com/go/v4/auth"
	"github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1/minimatchv1connect"
)

type Verifier interface {
	VerifyIDToken(context.Context, string) (string, error)
}

type Actor struct {
	UID         string
	AppleLinked bool
}

type actorVerifier interface {
	VerifyActor(context.Context, string) (Actor, error)
}

type AppCheckVerifier interface {
	VerifyToken(string) error
}

type FirebaseVerifier struct {
	client *auth.Client
}

func NewFirebaseVerifier(client *auth.Client) *FirebaseVerifier {
	return &FirebaseVerifier{client: client}
}

func (v *FirebaseVerifier) VerifyIDToken(ctx context.Context, value string) (string, error) {
	actor, err := v.VerifyActor(ctx, value)
	return actor.UID, err
}

func (v *FirebaseVerifier) VerifyActor(ctx context.Context, value string) (Actor, error) {
	token, err := v.client.VerifyIDToken(ctx, value)
	if err != nil {
		return Actor{}, err
	}
	return actorFromToken(token), nil
}

func actorFromToken(token *auth.Token) Actor {
	identities, ok := token.Firebase.Identities["apple.com"].([]interface{})
	appleLinked := ok && len(identities) > 0
	return Actor{UID: token.UID, AppleLinked: appleLinked}
}

type FirebaseAppCheckVerifier struct {
	client *appcheck.Client
}

func NewFirebaseAppCheckVerifier(client *appcheck.Client) *FirebaseAppCheckVerifier {
	return &FirebaseAppCheckVerifier{client: client}
}

func (v *FirebaseAppCheckVerifier) VerifyToken(value string) error {
	_, err := v.client.VerifyToken(value)
	return err
}

type actorKey struct{}

func ActorID(ctx context.Context) (string, bool) {
	actor, ok := ActorFromContext(ctx)
	return actor.UID, ok
}

func ActorFromContext(ctx context.Context) (Actor, bool) {
	actor, ok := ctx.Value(actorKey{}).(Actor)
	return actor, ok && actor.UID != ""
}

func RequireAppleLinked(ctx context.Context) (Actor, error) {
	actor, ok := ActorFromContext(ctx)
	if !ok || !actor.AppleLinked {
		return Actor{}, connect.NewError(connect.CodeUnauthenticated, errors.New("Apple-linked account required"))
	}
	return actor, nil
}

func NewInterceptor(verifier Verifier) connect.UnaryInterceptorFunc {
	return newInterceptor(verifier, nil, false)
}

func NewDailyProtectedInterceptor(
	verifier Verifier,
	appCheckVerifier AppCheckVerifier,
) connect.UnaryInterceptorFunc {
	return newInterceptor(verifier, appCheckVerifier, true)
}

func newInterceptor(
	verifier Verifier,
	appCheckVerifier AppCheckVerifier,
	protectDaily bool,
) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, request connect.AnyRequest) (connect.AnyResponse, error) {
			token, ok := headerToken(request, "Authorization", "Bearer")
			if !ok {
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("missing bearer token"))
			}
			actor := Actor{}
			var err error
			if claimsVerifier, ok := verifier.(actorVerifier); ok {
				actor, err = claimsVerifier.VerifyActor(ctx, token)
			} else {
				actor.UID, err = verifier.VerifyIDToken(ctx, token)
			}
			if err != nil || actor.UID == "" {
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid Firebase ID token"))
			}
			if protectDaily && isDailyProcedure(request.Spec().Procedure) {
				appCheckToken, ok := headerToken(request, "X-Firebase-AppCheck", "")
				if !ok || appCheckVerifier == nil || appCheckVerifier.VerifyToken(appCheckToken) != nil {
					return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid Firebase App Check token"))
				}
			}
			return next(context.WithValue(ctx, actorKey{}, actor), request)
		}
	}
}

func headerToken(request connect.AnyRequest, name string, scheme string) (string, bool) {
	values := request.Header().Values(name)
	if len(values) != 1 {
		return "", false
	}
	value := strings.TrimSpace(values[0])
	if scheme == "" {
		return value, value != ""
	}
	headerScheme, token, found := strings.Cut(value, " ")
	token = strings.TrimSpace(token)
	return token, found && strings.EqualFold(headerScheme, scheme) && token != ""
}

func isDailyProcedure(procedure string) bool {
	switch procedure {
	case minimatchv1connect.MiniMatchServiceGetDailyGlobalTableProcedure,
		minimatchv1connect.MiniMatchServiceLockDailyGlobalPickProcedure:
		return true
	default:
		return false
	}
}
