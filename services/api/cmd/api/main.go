package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"connectrpc.com/connect"
	firebase "firebase.google.com/go/v4"
	"github.com/YazdanRa/mini-match/services/api/gen/minimatch/v1/minimatchv1connect"
	"github.com/YazdanRa/mini-match/services/api/internal/authn"
	"github.com/YazdanRa/mini-match/services/api/internal/server"
	"github.com/YazdanRa/mini-match/services/api/internal/store"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
	if projectID == "" {
		log.Fatal("GOOGLE_CLOUD_PROJECT is required")
	}

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
	if err != nil {
		log.Fatalf("initialize Firebase: %v", err)
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		log.Fatalf("initialize Firebase Auth: %v", err)
	}
	firestoreClient, err := app.Firestore(ctx)
	if err != nil {
		log.Fatalf("initialize Firestore: %v", err)
	}
	defer firestoreClient.Close()

	path, handler := minimatchv1connect.NewMiniMatchServiceHandler(
		server.New(store.NewFirestoreRepository(firestoreClient)),
		connect.WithInterceptors(authn.NewInterceptor(authn.NewFirebaseVerifier(authClient))),
	)

	protocols := new(http.Protocols)
	protocols.SetHTTP1(true)
	protocols.SetUnencryptedHTTP2(true)
	log.Printf("listening on :%s", port)
	log.Fatal((&http.Server{
		Addr:      ":" + port,
		Handler:   newHandler(path, handler),
		Protocols: protocols,
	}).ListenAndServe())
}

func newHandler(apiPath string, apiHandler http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.Handle(apiPath, apiHandler)
	return mux
}
