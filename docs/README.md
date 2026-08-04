# Design sketches

- `home-create-join.png` — create or join a table
- `lobby-ready.png` — lobby readiness
- `pick-number-dark.png` — compact number picker
- `lobby-lock-number.png` — arbitrary-number entry, lock state, and invites
- `result-reveal-alternate.png` — alternate result treatment
- `result-lowest-unique.png` — archived result and score treatment

Approved flow: create or join a table, then the host starts a round. Everyone locks any non-negative integer, and the host reveals after everyone locks. Duplicate picks are ineligible; the lowest number chosen exactly once wins. Every round is independent, and its result returns players to the lobby until the host starts the next round. This rule supersedes contradictory copy in a sketch.

## Icon concepts

- `icons/matching-number-tiles.png` — concept 1
- `icons/lowest-number-target.png` — concept 2
- `icons/player-chat-tokens.png` — concept 3

These are archived explorations, not production app-icon assets yet.
