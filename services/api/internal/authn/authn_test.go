package authn

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"connectrpc.com/connect"
	"firebase.google.com/go/v4/auth"
	"github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1/minimatchv1connect"
	"google.golang.org/protobuf/types/known/emptypb"
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

func TestActorFromTokenUsesVerifiedAppleIdentityClaim(t *testing.T) {
	tests := []struct {
		name       string
		firebase   auth.FirebaseInfo
		wantLinked bool
	}{
		{
			name: "linked even when another provider signed in",
			firebase: auth.FirebaseInfo{
				SignInProvider: "password",
				Identities:     map[string]interface{}{"apple.com": []interface{}{"apple-user"}},
			},
			wantLinked: true,
		},
		{
			name:       "sign-in provider alone is not a linked identity",
			firebase:   auth.FirebaseInfo{SignInProvider: "apple.com"},
			wantLinked: false,
		},
		{
			name:       "unlinked",
			firebase:   auth.FirebaseInfo{Identities: map[string]interface{}{}},
			wantLinked: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			actor := actorFromToken(&auth.Token{UID: "maya", Firebase: test.firebase})
			if actor.UID != "maya" || actor.AppleLinked != test.wantLinked {
				t.Fatalf("actor = %+v, want UID maya, AppleLinked %v", actor, test.wantLinked)
			}
		})
	}
}

type fakeActorVerifier map[string]Actor

func (v fakeActorVerifier) VerifyIDToken(ctx context.Context, token string) (string, error) {
	actor, err := v.VerifyActor(ctx, token)
	return actor.UID, err
}

func (v fakeActorVerifier) VerifyActor(_ context.Context, token string) (Actor, error) {
	actor, ok := v[token]
	if !ok {
		return Actor{}, errors.New("invalid token")
	}
	return actor, nil
}

type fakeAppCheckVerifier map[string]bool

func (v fakeAppCheckVerifier) VerifyToken(token string) error {
	if !v[token] {
		return errors.New("invalid App Check token")
	}
	return nil
}

func TestDailyAppCheckIsProcedureScoped(t *testing.T) {
	const (
		getDaily  = minimatchv1connect.MiniMatchServiceGetDailyGlobalTableProcedure
		lockDaily = minimatchv1connect.MiniMatchServiceLockDailyGlobalPickProcedure
		social    = minimatchv1connect.MiniMatchServiceGetTableProcedure
	)
	interceptor := NewDailyProtectedInterceptor(
		fakeActorVerifier{"firebase": {UID: "maya", AppleLinked: true}},
		fakeAppCheckVerifier{"app-check": true},
	)

	for _, procedure := range []string{getDaily, lockDaily} {
		t.Run(procedure+" rejects missing token", func(t *testing.T) {
			if status := callStatus(t, procedure, interceptor, ""); status != http.StatusUnauthorized {
				t.Fatalf("status = %v, want unauthorized", status)
			}
		})
		t.Run(procedure+" rejects invalid token", func(t *testing.T) {
			if status := callStatus(t, procedure, interceptor, "invalid"); status != http.StatusUnauthorized {
				t.Fatalf("status = %v, want unauthorized", status)
			}
		})
		t.Run(procedure+" accepts valid token", func(t *testing.T) {
			if status := callStatus(t, procedure, interceptor, "app-check"); status != http.StatusOK {
				t.Fatalf("status = %v, want success", status)
			}
		})
	}
	t.Run("Daily RPC rejects duplicate tokens", func(t *testing.T) {
		if status := callStatus(t, getDaily, interceptor, "app-check", "app-check"); status != http.StatusUnauthorized {
			t.Fatalf("status = %v, want unauthorized", status)
		}
	})
	t.Run("Daily RPC fails closed without an App Check verifier", func(t *testing.T) {
		withoutVerifier := NewDailyProtectedInterceptor(
			fakeActorVerifier{"firebase": {UID: "maya", AppleLinked: true}},
			nil,
		)
		if status := callStatus(t, getDaily, withoutVerifier, "app-check"); status != http.StatusUnauthorized {
			t.Fatalf("status = %v, want unauthorized", status)
		}
	})

	t.Run("social RPC remains bearer-only", func(t *testing.T) {
		if status := callStatus(t, social, interceptor, "invalid"); status != http.StatusOK {
			t.Fatalf("status = %v, want success", status)
		}
	})
}

func TestRequireAppleLinked(t *testing.T) {
	interceptor := NewInterceptor(fakeActorVerifier{
		"apple":    {UID: "maya", AppleLinked: true},
		"password": {UID: "maya"},
	})
	next := interceptor(func(ctx context.Context, _ connect.AnyRequest) (connect.AnyResponse, error) {
		_, err := RequireAppleLinked(ctx)
		return nil, err
	})

	for token, wantCode := range map[string]connect.Code{
		"apple":    connect.CodeUnknown,
		"password": connect.CodeUnauthenticated,
	} {
		request := connect.NewRequest(&struct{}{})
		request.Header().Set("Authorization", "Bearer "+token)
		_, err := next(context.Background(), request)
		if code := connect.CodeOf(err); code != wantCode {
			t.Errorf("token %q code = %v, want %v", token, code, wantCode)
		}
	}
}

func callStatus(
	t *testing.T,
	procedure string,
	interceptor connect.UnaryInterceptorFunc,
	appCheckTokens ...string,
) int {
	t.Helper()
	handler := connect.NewUnaryHandler(
		procedure,
		func(ctx context.Context, _ *connect.Request[emptypb.Empty]) (*connect.Response[emptypb.Empty], error) {
			actor, ok := ActorFromContext(ctx)
			if !ok || actor.UID != "maya" || !actor.AppleLinked {
				t.Fatalf("actor = %+v, %v", actor, ok)
			}
			return connect.NewResponse(&emptypb.Empty{}), nil
		},
		connect.WithInterceptors(interceptor),
	)
	request := httptest.NewRequest(http.MethodPost, procedure, nil)
	request.Header.Set("Content-Type", "application/proto")
	request.Header.Set("Authorization", "Bearer firebase")
	for _, token := range appCheckTokens {
		if token != "" {
			request.Header.Add("X-Firebase-AppCheck", token)
		}
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response.Code
}
