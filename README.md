# Mini Match

Mini Match is a real-time social game: the host starts a round, everyone privately locks a non-negative integer, then the host reveals. The lowest number chosen exactly once wins. Every round is independent, and players return to the lobby until the host starts the next one.

## Repository

- `apps/apple/` — conventional Xcode project for the current iPhone SwiftUI app and future Apple targets
- `services/api/` — Go command service serving Connect RPC and gRPC
- `proto/` — versioned protobuf contract managed by Buf
- `docs/` — product sketches and icon explorations

Go keeps the server small and fast to start on Cloud Run. One generated Connect handler serves Connect, gRPC, and gRPC-Web from the same protobuf API. Buf makes that contract suitable for later Swift, Kotlin, and web TypeScript clients without maintaining parallel models. Firestore is the persistence and live-observation boundary; it provides cross-platform listeners without operating a separate streaming service.

## State flow

1. `CreateTable` or `JoinTable` mutates authoritative state through the API.
2. The iPhone client polls authenticated `GetTable` while its lobby is active for joins, lock status, versions, and reveal results. The same safe state is also written to the Firestore `table_views` projection for future native listeners.
3. `LockPick` stores the caller's pick only in server-readable state. Other players see `locked = true`, never the value.
4. `RevealRound` is host-only and succeeds only for the current round after every current player locks. It resolves the lowest unique pick, publishes `last_result`, clears private picks, and returns the table to the lobby.
5. `BeginRound` is host-only and opens the next independent round for everyone in the lobby. The deprecated `StartRound` name remains as a wire-compatible reveal alias.

Active authenticated table traffic renews a private two-minute membership lease. A returning member can resume the saved table while its row is retained; active peers evict expired rows during polling, promote the next host when necessary, and cancel an active round if fewer than two players remain. Lease deadlines stay in the private table document and never appear in the client-readable projection.

Firestore uses separate server-only `tables` documents and client-readable `table_views` projections because security rules cannot hide selected fields within one readable document. Each table player stores the Game Center display name (editable before joining) and a random app-owned fallback avatar ID in both projections; Game Center photos remain on-device. Every RPC requires a Firebase ID token; the verified Firebase UID is the table player identity. Authenticated Game Center players also send Apple's signed identity payload so the backend can bind the table player to the current Game Center participant. Firestore transactions update both views atomically, while the in-memory repository keeps domain tests fast.

## Local validation

Requirements: Go 1.25+, Buf, and Xcode.

```sh
cd proto
buf format --diff --exit-code
buf lint
buf build

cd ../services/api
buf generate ../../proto
go test -race ./...
GOOGLE_CLOUD_PROJECT=mini-match-20260729 \
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
  FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  go run ./cmd/api
```

Open `apps/apple/MiniMatch/MiniMatch.xcodeproj` in Xcode to build the iPhone app. Generated Go source lives in the repository; regenerate it only when the protobuf contract changes. Swift/Kotlin/TypeScript generation waits until those clients consume the API.

The Apple target uses bundle identifier `com.yazdanra.minimatch`, configures Firebase from a local `GoogleService-Info.plist` excluded from source control, and sends Connect JSON commands to the production Cloud Run origin. It signs players in anonymously on first use and lets them link that identity to Sign in with Apple. Firebase's Apple provider is enabled for the same bundle ID; the client uses a secure nonce, checks credential revocation, requests no unused profile scopes, and supports reauthenticated token revocation, saved-table profile anonymization, and account deletion. Game Center authenticates at launch, supplies the default nickname and local profile photo, and disables custom multiplayer when Screen Time restricts it.

## Deployment outline

The backend runs in Firebase/GCP project `mini-match-20260729`, with Firestore and anonymous Authentication enabled. Deploy rules with `firebase deploy --only firestore:rules --project mini-match-20260729`, then deploy `services/api` to Cloud Run using the dedicated runtime service account and Application Default Credentials. Cloud Run must use end-to-end HTTP/2 (`gcloud run deploy ... --source services/api --use-http2`) for native gRPC; Connect works over HTTP/1.1 or HTTP/2. Cloud Run allows public invocation for mobile clients, while the service itself rejects requests without a valid Firebase bearer token.

Release the independent-round Apple client and backend together: installed clients from the first-to-five contract cannot start explicit lobby rounds. Rewrite any legacy `finished` documents in the `table_views` projection before direct Firestore listeners consume it.

Before TestFlight, select the Apple developer team and enable Sign in with Apple for the `com.yazdanra.minimatch` App ID in the Apple Developer portal. Add Firebase App Check and an application-level abuse limit before broad public launch. Then archive a Release build in Xcode and distribute it through App Store Connect (or configure Xcode Cloud for the same archive/test workflow).
