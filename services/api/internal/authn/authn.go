package authn

import (
	"context"
	"errors"
	"strings"

	"connectrpc.com/connect"
	"firebase.google.com/go/v4/auth"
)

type Verifier interface {
	VerifyIDToken(context.Context, string) (string, error)
}

type FirebaseVerifier struct {
	client *auth.Client
}

func NewFirebaseVerifier(client *auth.Client) *FirebaseVerifier {
	return &FirebaseVerifier{client: client}
}

func (v *FirebaseVerifier) VerifyIDToken(ctx context.Context, value string) (string, error) {
	token, err := v.client.VerifyIDToken(ctx, value)
	if err != nil {
		return "", err
	}
	return token.UID, nil
}

type actorKey struct{}

func ActorID(ctx context.Context) (string, bool) {
	actor, ok := ctx.Value(actorKey{}).(string)
	return actor, ok && actor != ""
}

func NewInterceptor(verifier Verifier) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, request connect.AnyRequest) (connect.AnyResponse, error) {
			values := request.Header().Values("Authorization")
			if len(values) != 1 {
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("missing bearer token"))
			}
			value := values[0]
			scheme, token, found := strings.Cut(value, " ")
			if !found || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(token) == "" {
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("missing bearer token"))
			}
			uid, err := verifier.VerifyIDToken(ctx, strings.TrimSpace(token))
			if err != nil || uid == "" {
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid Firebase ID token"))
			}
			return next(context.WithValue(ctx, actorKey{}, uid), request)
		}
	}
}
