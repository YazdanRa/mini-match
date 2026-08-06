# Security Policy

## Supported Versions

Security fixes target the current default branch and the latest Mini Match build
made available through TestFlight or the App Store. Older builds are not supported.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately by emailing
[minimatch@yr.dev](mailto:minimatch@yr.dev) with `Mini Match security` in the
subject. Do not open a public GitHub issue for a suspected vulnerability.

Include the affected component or version, the security impact, prerequisites,
and reproducible steps. Remove authentication tokens, personal data, and other
secrets from the report. Please allow time to investigate and coordinate a fix
before public disclosure.

Use the [public issue tracker](https://github.com/YazdanRa/mini-match/issues)
only for non-sensitive support and privacy questions.

## System and Scope

This policy covers:

- The SwiftUI iPhone app under `apps/apple/`.
- The internet-facing Go Connect/gRPC API under `services/api/`.
- The protobuf contract under `proto/`, Firestore rules and projections, and
  deployment workflows.
- The static website under `apps/web/` when a weakness could affect visitors or
  Mini Match's security claims.

Mini Match depends on Apple Game Center and Sign in with Apple, Firebase
Authentication and Firestore, Google Cloud Run, and GitHub Pages. Vulnerabilities
in those services themselves should be reported to their providers; weaknesses
in Mini Match's configuration or use of them remain in scope.

## Threat Model and Security Invariants

Clients, network requests, join codes, profile fields, and Game Center identity
payloads are untrusted. The following properties must hold:

- Every game and account RPC requires exactly one valid Firebase bearer token.
  `GET /health` is the sole intentionally unauthenticated endpoint. The verified
  Firebase UID is the authoritative actor identity.
- Daily Table RPCs additionally require a valid Firebase App Check token and an
  Apple-linked Firebase account.
- Game Center identity data is trusted only after the server verifies Apple's
  certificate chain and the signature covering the team player ID, bundle
  identifier, timestamp, and salt. The verified Game Center identity is then
  associated with the Firebase actor.
- Table membership, host-only actions, profile deletion, and other authorization
  decisions are derived from the authenticated actor, not caller-supplied player
  identifiers.
- An authenticated user who knows a valid party code may join that table. The
  party code is an invitation and discovery mechanism, not authorization to read
  unrelated tables.
- Picks remain server-only until a valid host reveal after all current players
  have locked. Game rules and state transitions remain server-authoritative.
- Daily Table picks remain server-only. After the UTC cutoff, clients receive
  only the aggregate result and their own pick and outcome.
- Firestore clients can read only the safe `table_views` projection for tables
  they belong to. They cannot list or write projections, access private table
  documents, or receive unrevealed picks, private presence leases, or Game
  Center identifiers.
- Private and public table state is updated consistently so partial writes
  cannot leak or corrupt game state.
- Credentials and signing material must not be committed. Production deployment
  should use short-lived GitHub OIDC credentials and least-privilege deployment,
  build, and runtime identities.

## Reportable Findings and Severity

A finding is reportable when it has a realistic path to compromise
confidentiality, integrity, availability, or account ownership. Examples include
authentication or authorization bypasses, cross-table access, player
impersonation, pre-reveal pick disclosure, Game Center identity forgery or
replay, unauthorized profile deletion, remote code execution, credential
exposure, deployment compromise, and resource-exhaustion flaws reachable without
excessive traffic.

Severity depends on practical reachability, required privileges or user
interaction, affected users, and impact. A missing best practice without an
exploitable security consequence is not by itself a vulnerability.

## Out of Scope and Testing Safety

The following are not generally reportable unless Mini Match's code or
configuration creates the weakness:

- Vulnerabilities wholly within Apple, Google, Firebase, GitHub, or a user's
  device or account.
- Information intentionally disclosed to table participants after a valid
  reveal.
- Social engineering, spam, and denial-of-service testing that requires
  sustained or disruptive traffic.

Do not access another person's data, retain personal data, degrade the production
service, or perform destructive testing. Use test accounts and stop once you
have enough evidence to explain the issue.

## Known Limitations

Application-level abuse limiting remains planned before broad public release.
Stored social-table records do not currently have a fixed retention period.
These limitations are not blanket exclusions: report a concrete exploit or
exposure through the private channel above.
