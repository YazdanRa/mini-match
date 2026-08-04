# Mini Match

Mini Match is a real-time social number game for iPhone. The host starts each independent round, players privately lock a non-negative integer, and the lowest number chosen exactly once wins.

## Game theory background

Mini Match is based on a zero-indexed variant of the well-studied **Lowest Unique Positive Integer (LUPI)** game. In the classic game, players independently and simultaneously choose a positive integer. Duplicate choices are eliminated, and the player with the lowest remaining unique number wins. If every choice is duplicated, nobody wins. Mini Match keeps that strategic core while allowing non-negative integers, including zero. A large-scale Swedish version of LUPI was offered under the name **Limbo**.

The puzzle is the tension between choosing low and staying unique: obvious low numbers attract collisions, while a high unique number can still be beaten. The papers below study randomized symmetric mixed-strategy equilibria rather than one always-best pick. Some large-population asymptotic models spread choices across a low range with an effective cutoff on the order of `N / log(N)`. This is not a universal rule: the exact equilibrium depends on the number of players, allowed range, and assumptions of the model. In the unbounded, exactly-three-player formulation, the unique symmetric equilibrium has full support and a constant hazard rate.

LUPI has been studied theoretically, in laboratory experiments, and through data from the Swedish Limbo lottery:

- [Testing Game Theory in the Field: Swedish LUPI Lottery Games](https://www.stat.berkeley.edu/~aldous/157/Papers/ostling.pdf) — Robert Östling, Joseph Tao-yi Wang, Eileen Y. Chou, and Colin F. Camerer
- [Equilibrium Solution to the Lowest Unique Positive Integer Game](https://arxiv.org/pdf/1001.1065) — Seung Ki Baek and Sebastian Bernhardsson
- [Exact Asymptotics and Continuous Approximations for the Lowest Unique Positive Integer Game](https://doi.org/10.1007/s00182-023-00881-0) — Arvind Srinivasan and Burton Simon
- [The Three-player Lowest Unique Number Game](https://doi.org/10.1016/j.econlet.2025.112299) — Balázs Szentes

For approachable discussions, see [Mathematics Stack Exchange](https://math.stackexchange.com/questions/80714/game-theory-choosing-the-smallest-number-not-chosen-yet), [MathOverflow](https://mathoverflow.net/questions/27004/lowest-unique-bid), and the [r/GAMETHEORY community discussion](https://www.reddit.com/r/GAMETHEORY/comments/1fdk0s5/lowest_unique_positive_integer_gamelimbo/).

## Features

- Private simultaneous picks; only each player's lock status is shared before the reveal
- Host-controlled rounds with a full result reveal after every player locks
- Invite-only Game Center multiplayer and shareable party codes
- Live lobby status, reconnectable sessions, and automatic host promotion
- Game Center profiles, profile photos, and achievements
- Sign in with Apple account linking and profile controls
- English, French, and Spanish localization with accessible SwiftUI controls
