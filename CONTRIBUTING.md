# Contributing

## Repository layout

- `apps/apple/` — the Xcode project for the iPhone SwiftUI app and future Apple targets
- `services/api/` — the Go service that serves Connect RPC and gRPC
- `proto/` — the versioned protobuf contract managed by Buf
- `docs/` — Game Center achievement metadata

Go keeps the server small and fast to start on Cloud Run. One generated Connect handler serves Connect, gRPC, and gRPC-Web from the same protobuf API. Buf keeps the contract suitable for future Swift, Kotlin, and TypeScript clients without parallel hand-written models. Firestore is the persistence and live-observation boundary, avoiding a separate streaming service.

## State flow

1. `CreateTable` or `JoinTable` mutates authoritative state through the API.
2. The iPhone client polls authenticated `GetTable` while its lobby is active. The same safe state is written to the Firestore `table_views` projection for future native listeners.
3. `LockPick` stores the caller's pick only in server-readable state. Other players see `locked = true`, never the value.
4. `RevealRound` is host-only and succeeds after every current player locks. It resolves the lowest unique pick, publishes `last_result`, clears private picks, and returns the table to the lobby.
5. `BeginRound` is host-only and opens the next independent round. The deprecated `StartRound` name remains as a wire-compatible reveal alias.

Active authenticated table traffic renews a private two-minute membership lease. A returning member can resume a retained table. Active peers evict expired members during polling, promote the next host when needed, and cancel an active round if fewer than two players remain. Lease deadlines stay private.

Firestore uses server-only `tables` documents and client-readable `table_views` projections because security rules cannot hide selected fields within one readable document. Every RPC requires a Firebase ID token, and the verified Firebase UID identifies the table player. Game Center players also send Apple's signed identity payload so the backend can bind them to the current Game Center participant. Firestore transactions update both views atomically; the in-memory repository keeps domain tests fast.

The Daily Table is a separate hostless domain. The server derives its UTC date and cutoff, stores one immutable private pick per verified Game Center identity, and settles overdue rounds on the first Daily request after cutoff. Daily responses expose only aggregate results and the requesting player's own pick and outcome. Private entries and per-UID claims expire seven days after settlement; aggregate summaries and pseudonymous Daily-win totals remain. Daily RPCs also require Firebase App Check.

## Requirements

- Go 1.25 or later
- Buf
- Xcode
- Firebase CLI for Firestore rules deployment
- Prek for repository hooks

## Local validation

Validate the protobuf contract and server from the repository root:

```sh
cd proto
buf format --diff --exit-code
buf lint
buf build

cd ../services/api
buf generate ../../proto
go test -race ./...
```

Run the server against local Firebase emulators:

```sh
cd services/api
GOOGLE_CLOUD_PROJECT=mini-match-20260729 \
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
  FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  go run ./cmd/api
```

Generated Go source is committed. Regenerate it only when the protobuf contract changes. Swift, Kotlin, and TypeScript generation can be added when those clients consume the API.

Run repository hooks before submitting a change:

```sh
prek run --all-files
git diff --check
```

Use Conventional Commits for commit messages.

## Apple app setup

Open `apps/apple/MiniMatch/MiniMatch.xcodeproj` in Xcode. The app uses bundle identifier `com.yazdanra.minimatch` and includes `GoogleService-Info.plist` in the `MiniMatch` target. This is public, non-secret Firebase client configuration: the API key identifies the Firebase project, while bundle-ID and API restrictions limit its use. Firebase Authentication, server-side authorization, and Security Rules—not the key—control backend and data access. Never add service-account keys, server credentials, or private keys to this file. A clean checkout also needs valid signing for the configured team and App ID.

The App ID and provisioning profile require Game Center, Group Activities, Sign in with Apple, and App Attest. Configure the matching iOS app in Firebase, enable anonymous authentication and the Apple provider, register App Attest for App Check, and use the same bundle identifier. The client sends Connect JSON commands to the production Cloud Run origin. Daily Table requests require an Apple-linked Firebase account, a fresh Game Center identity signature, and an App Check token.

## Production server deployment

The backend targets GCP project `mini-match-20260729`, region `northamerica-northeast2`, and Cloud Run service `mini-match-api`. [The deployment workflow](.github/workflows/deploy-server.yml) is manually dispatched, runs the race-enabled Go test suite, deploys `services/api` to Cloud Run, and verifies the server's unauthenticated health endpoint.

The workflow uses GitHub Actions OIDC with Google Cloud Workload Identity Federation, so it does not require a long-lived service account key or GitHub secret. It deploys with separate deployment, build, and runtime service accounts and enables end-to-end HTTP/2 for native gRPC. Cloud Run permits public invocation for mobile clients, while the application rejects requests without a valid Firebase bearer token.

### GitHub environment

Create a GitHub environment named `production`, restrict its deployment branches to `master`, and define these environment variables:

| Variable | Value |
| --- | --- |
| `GCP_PROJECT_ID` | `mini-match-20260729` |
| `GCP_REGION` | `northamerica-northeast2` |
| `CLOUD_RUN_SERVICE` | `mini-match-api` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full provider resource name, such as `projects/704518244082/locations/global/workloadIdentityPools/github-actions/providers/mini-match` |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | Deployment service account email |
| `CLOUD_RUN_RUNTIME_SERVICE_ACCOUNT` | Runtime service account email |
| `CLOUD_RUN_BUILD_SERVICE_ACCOUNT` | Full build service account resource name: `projects/PROJECT_ID/serviceAccounts/EMAIL` |

The workflow must exist on the default branch before GitHub exposes its manual dispatch control.

### Required IAM

Grant only the permissions needed by the workflow:

- The GitHub Workload Identity principal needs `roles/iam.workloadIdentityUser` on the deployment service account.
- The deployment service account needs `roles/run.sourceDeveloper` on the project.
- The deployment service account needs `roles/iam.serviceAccountUser` on the build and runtime service accounts.
- The build service account needs `roles/run.builder` on the project.

### Firestore rules

The server workflow does not deploy Firestore security rules. Deploy them separately when `services/api/firestore.rules` changes:

```sh
firebase deploy --only firestore:rules --project mini-match-20260729
```

### Dispatch

After the workflow reaches the default branch, open **Actions → Deploy server → Run workflow**, select `master`, and run it. A successful run publishes the Cloud Run URL on the `production` environment deployment.

## Apple release

Confirm that the Release configuration signs with the intended Apple team and that the App ID has Game Center, Group Activities, and Sign in with Apple enabled. Archive the app in Xcode and distribute it through App Store Connect or an equivalent Xcode Cloud archive workflow.

Before broad public release, enable App Check enforcement for the registered iOS app and add application-level abuse limits.
