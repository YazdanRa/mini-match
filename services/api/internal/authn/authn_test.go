package authn

import (
	"context"
	"errors"
	"testing"

	"connectrpc.com/connect"
)

type fakeVerifier map[string]string

func (v fakeVerifier) VerifyIDToken(_ context.Context, token string) (string, error) {
	uid, ok := v[token]
	if !ok {
		return "", errors.New("invalid token")
	}
	return uid, nil
}

func TestInterceptorRequiresVerifiedBearerToken(t *testing.T) {
	interceptor := NewInterceptor(fakeVerifier{"valid": "maya"})
	next := interceptor(func(ctx context.Context, _ connect.AnyRequest) (connect.AnyResponse, error) {
		uid, ok := ActorID(ctx)
		if !ok || uid != "maya" {
			t.Fatalf("actor = %q, %v", uid, ok)
		}
		return nil, nil
	})

	for name, authorization := range map[string]string{
		"missing":      "",
		"wrong scheme": "Basic valid",
		"invalid":      "Bearer invalid",
	} {
		t.Run(name, func(t *testing.T) {
			request := connect.NewRequest(&struct{}{})
			request.Header().Set("Authorization", authorization)
			if _, err := next(context.Background(), request); connect.CodeOf(err) != connect.CodeUnauthenticated {
				t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
			}
		})
	}

	request := connect.NewRequest(&struct{}{})
	request.Header().Set("Authorization", "Bearer valid")
	if _, err := next(context.Background(), request); err != nil {
		t.Fatal(err)
	}

	request.Header().Add("Authorization", "Bearer valid")
	if _, err := next(context.Background(), request); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("duplicate header code = %v, want unauthenticated", connect.CodeOf(err))
	}
}
