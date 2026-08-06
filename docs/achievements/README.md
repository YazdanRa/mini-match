# Game Center achievements

Mini Match has 14 active, visible, nonrepeatable Game Center achievements worth **500 points**. Every active achievement is associated with the `com.yazdanra.minimatch.play` Game Activity. The former 25-point **Perfect Zero** achievement is archived because picks must now be positive integers.

`Implemented` below means the app/backend reporting path and local `.gamekit` metadata exist in source. It does not mean the achievement is public: App Store Connect synchronization, review, and physical-device verification remain release gates.

## Catalog

| Status | Achievement | Localized name (French / Spanish / Italian) | Stable identifier | Points | Exact unlock criterion | Future image direction |
| --- | --- | --- | --- | ---: | --- | --- |
| Implemented (existing) | First Win | Première victoire / Primera victoria / Prima vittoria | `com.yazdanra.minimatch.achievement.firstWin` | 10 | The authoritative revealed result names the player as winner for the first time. | A single raised pennant with a bright `1` token. |
| Retired (archived) | Perfect Zero | Zéro parfait / Cero perfecto / Zero perfetto | `com.yazdanra.minimatch.achievement.zeroWin` | 25 | No longer earnable; zero is not a valid pick. The identifier remains reserved for historical compatibility. | Existing artwork retained for the archived achievement. |
| Implemented (renamed) | Party Champion | Champion du groupe / Campeón del grupo / Campione del gruppo | `com.yazdanra.minimatch.achievement.fourPlayerWin` | 25 | Win an authoritative revealed round with at least 4 revealed participants. | A crown above four distinct player tokens. This achievement was previously named **Full Table**; its stable identifier and criterion are unchanged. |
| Implemented (new) | High Four | Quatre en force / Cuatro triunfal / Quattro vincente | `com.yazdanra.minimatch.achievement.pickFourWin` | 10 | Win an authoritative revealed round with the exact pick `4`. | A bold `4` token rising above the board. |
| Implemented (new) | Great Eight | Huit magnifique / Ocho magnífico / Otto magnifico | `com.yazdanra.minimatch.achievement.pickEightWin` | 10 | Win an authoritative revealed round with the exact pick `8`. | A luminous figure-eight made from two game tokens. |
| Implemented (new) | Sweet Sixteen | Seize en or / Dulces dieciséis / Sedici d’oro | `com.yazdanra.minimatch.achievement.pickSixteenWin` | 10 | Win an authoritative revealed round with the exact pick `16`. | A celebratory `16` wrapped by a simple ribbon. |
| Implemented (new) | Back-to-Back | Deux de suite / Dos seguidas / Due di fila | `com.yazdanra.minimatch.achievement.twoWinStreak` | 25 | The player's authoritative current win streak reaches at least 2. | Two linked winner crowns or adjacent gold tokens. |
| Implemented (new) | Four on Fire | Quatre de suite / Cuatro seguidas / Quattro di fila | `com.yazdanra.minimatch.achievement.fourWinStreak` | 50 | The player's authoritative current win streak reaches at least 4. | Four game tokens forming a controlled flame. |
| Implemented (new) | Proven Winner | Victoire confirmée / Victoria confirmada / Vincitore affermato | `com.yazdanra.minimatch.achievement.sixteenRoundWins` | 25 | The player's authoritative lifetime round-win total reaches at least 16. | A laurel medal with 16 small notches. |
| Implemented (new) | Round Veteran | Vétéran des manches / Veterano de las rondas / Veterano delle manche | `com.yazdanra.minimatch.achievement.thirtyTwoRoundWins` | 50 | The player's authoritative lifetime round-win total reaches at least 32. | A seasoned shield bearing `32`. |
| Implemented (new) | Mini Match Legend | Légende de Mini Match / Leyenda de Mini Match / Leggenda di Mini Match | `com.yazdanra.minimatch.achievement.sixtyFourRoundWins` | 100 | The player's authoritative lifetime round-win total reaches at least 64. | A radiant Mini Match trophy bearing `64`. |
| Implemented (new) | Join the Crowd | Rejoignez la foule / Únete a la multitud / Unisciti alla folla | `com.yazdanra.minimatch.achievement.eightPlayerRound` | 10 | Appear in an authoritative revealed round with at least 8 revealed participants, regardless of result. | Eight colorful player tokens arranged in a ring. |
| Implemented (new) | Packed House | Salle comble / Sala llena / Tutto esaurito | `com.yazdanra.minimatch.achievement.sixteenPlayerRound` | 25 | Appear in an authoritative revealed round with at least 16 revealed participants, regardless of result. | A board filled by 16 compact player tokens. |
| Implemented (new) | Crowd Champion | Champion de la foule / Campeón de la multitud / Campione della folla | `com.yazdanra.minimatch.achievement.eightPlayerWin` | 50 | Win an authoritative revealed round with at least 8 revealed participants. | A crown floating above a ring of eight tokens. |
| Implemented (new) | House Champion | Champion de la salle / Campeón de la sala / Campione della sala | `com.yazdanra.minimatch.achievement.sixteenPlayerWin` | 100 | Win an authoritative revealed round with at least 16 revealed participants. | A large crown above a packed 16-token board. |

## Player-facing copy

The local Game Center bundle provides English, French, Spanish, and Italian names plus before-earned and after-earned descriptions for every achievement. The copy states the same thresholds as the catalog:

| Achievement | English before → after | French before → after | Spanish before → after | Italian before → after |
| --- | --- | --- | --- | --- |
| First Win | Win your first Mini Match round. → You won your first Mini Match round. | Remportez votre première manche de Mini Match. → Vous avez remporté votre première manche de Mini Match. | Gana tu primera ronda de Mini Match. → Has ganado tu primera ronda de Mini Match. | Vinci la tua prima manche di Mini Match. → Hai vinto la tua prima manche di Mini Match. |
| Perfect Zero (archived) | Win a round by choosing 0. → You won a round by choosing 0. | Remportez une manche en choisissant 0. → Vous avez remporté une manche en choisissant 0. | Gana una ronda eligiendo 0. → Has ganado una ronda eligiendo 0. | Vinci una manche scegliendo 0. → Hai vinto una manche scegliendo 0. |
| Party Champion | Win a round with at least four players. → You won a round with at least four players. | Remportez une manche avec au moins quatre joueurs. → Vous avez remporté une manche avec au moins quatre joueurs. | Gana una ronda con al menos cuatro jugadores. → Has ganado una ronda con al menos cuatro jugadores. | Vinci una manche con almeno quattro giocatori. → Hai vinto una manche con almeno quattro giocatori. |
| High Four | Win a round by choosing 4. → You won a round by choosing 4. | Remportez une manche en choisissant 4. → Vous avez remporté une manche en choisissant 4. | Gana una ronda eligiendo 4. → Has ganado una ronda eligiendo 4. | Vinci una manche scegliendo 4. → Hai vinto una manche scegliendo 4. |
| Great Eight | Win a round by choosing 8. → You won a round by choosing 8. | Remportez une manche en choisissant 8. → Vous avez remporté une manche en choisissant 8. | Gana una ronda eligiendo 8. → Has ganado una ronda eligiendo 8. | Vinci una manche scegliendo 8. → Hai vinto una manche scegliendo 8. |
| Sweet Sixteen | Win a round by choosing 16. → You won a round by choosing 16. | Remportez une manche en choisissant 16. → Vous avez remporté une manche en choisissant 16. | Gana una ronda eligiendo 16. → Has ganado una ronda eligiendo 16. | Vinci una manche scegliendo 16. → Hai vinto una manche scegliendo 16. |
| Back-to-Back | Win two consecutive rounds you play. → You won two consecutive rounds you played. | Remportez deux manches jouées consécutives. → Vous avez remporté deux manches jouées consécutives. | Gana dos rondas jugadas consecutivas. → Has ganado dos rondas jugadas consecutivas. | Vinci due manche consecutive a cui partecipi. → Hai vinto due manche consecutive a cui hai partecipato. |
| Four on Fire | Win four consecutive rounds you play. → You won four consecutive rounds you played. | Remportez quatre manches jouées consécutives. → Vous avez remporté quatre manches jouées consécutives. | Gana cuatro rondas jugadas consecutivas. → Has ganado cuatro rondas jugadas consecutivas. | Vinci quattro manche consecutive a cui partecipi. → Hai vinto quattro manche consecutive a cui hai partecipato. |
| Proven Winner | Win 16 rounds in total. → You won a total of 16 rounds. | Remportez 16 manches au total. → Vous avez remporté 16 manches au total. | Gana 16 rondas en total. → Has ganado 16 rondas en total. | Vinci 16 manche in totale. → Hai vinto 16 manche in totale. |
| Round Veteran | Win 32 rounds in total. → You won a total of 32 rounds. | Remportez 32 manches au total. → Vous avez remporté 32 manches au total. | Gana 32 rondas en total. → Has ganado 32 rondas en total. | Vinci 32 manche in totale. → Hai vinto 32 manche in totale. |
| Mini Match Legend | Win 64 rounds in total. → You won a total of 64 rounds. | Remportez 64 manches au total. → Vous avez remporté 64 manches au total. | Gana 64 rondas en total. → Has ganado 64 rondas en total. | Vinci 64 manche in totale. → Hai vinto 64 manche in totale. |
| Join the Crowd | Play a round with at least eight players. → You played a round with at least eight players. | Jouez une manche avec au moins huit joueurs. → Vous avez joué une manche avec au moins huit joueurs. | Juega una ronda con al menos ocho jugadores. → Has jugado una ronda con al menos ocho jugadores. | Gioca una manche con almeno otto giocatori. → Hai giocato una manche con almeno otto giocatori. |
| Packed House | Play a round with at least 16 players. → You played a round with at least 16 players. | Jouez une manche avec au moins 16 joueurs. → Vous avez joué une manche avec au moins 16 joueurs. | Juega una ronda con al menos 16 jugadores. → Has jugado una ronda con al menos 16 jugadores. | Gioca una manche con almeno 16 giocatori. → Hai giocato una manche con almeno 16 giocatori. |
| Crowd Champion | Win a round with at least eight players. → You won a round with at least eight players. | Remportez une manche avec au moins huit joueurs. → Vous avez remporté une manche avec au moins huit joueurs. | Gana una ronda con al menos ocho jugadores. → Has ganado una ronda con al menos ocho jugadores. | Vinci una manche con almeno otto giocatori. → Hai vinto una manche con almeno otto giocatori. |
| House Champion | Win a round with at least 16 players. → You won a round with at least 16 players. | Remportez une manche avec au moins 16 joueurs. → Vous avez remporté une manche avec au moins 16 joueurs. | Gana una ronda con al menos 16 jugadores. → Has ganado una ronda con al menos 16 jugadores. | Vinci una manche con almeno 16 giocatori. → Hai vinto una manche con almeno 16 giocatori. |

## Leaderboard

The lifetime-wins leaderboard uses `com.yazdanra.minimatch.wins` and is localized alongside the app:

| Locale | Name | Singular suffix | Plural suffix |
| --- | --- | --- | --- |
| English | Most Wins | win | wins |
| French | Plus de victoires | victoire | victoires |
| Spanish | Más victorias | victoria | victorias |
| Italian | Più vittorie | vittoria | vittorie |

## Canonical semantics

- Only an authoritative backend result after reveal can advance or unlock an achievement. Client polling order and lobby state are not achievement evidence.
- Revealed participant count is the number of selections in that result, not the number invited or the table's advertised capacity.
- Player-count achievements are inclusive thresholds. A 16-player round also satisfies the 4- and 8-player criteria; a win counts as participation.
- Picks must be positive integers. Pick achievements require the winning selection to equal the named number exactly.
- Win streaks span tables and sessions for the authenticated player. They count consecutive revealed rounds that player participates in. A participating loss or a participating no-winner round resets the streak; absence from a round does not.
- Lifetime totals and streaks come from the authoritative persisted player record. Threshold achievements use `>=`, so a counter that passes more than one tier may unlock every newly satisfied tier. Shared table responses carry only satisfied achievement identifiers, not exact private counters.
- Multiple achievements may unlock from one result. Pending reports are persisted per Game Center player, so reporting is idempotent, retryable across relaunches, and never blocks gameplay.
- All active achievements are visible before earning and nonrepeatable. Perfect Zero remains archived under its original identifier for historical compatibility.

## Artwork status

The three original achievements retain their existing localized artwork files, including Perfect Zero's archived assets. The 12 new achievements temporarily reference the existing English First Win JPEG so the `.gamekit` bundle remains structurally complete without committing duplicate placeholder files. Replace those shared references with purpose-built artwork following the catalog directions before App Store Connect publication.

## Implementation and validation

1. Persist total wins plus current and best win streaks against the verified player identity in the authoritative backend, updating them transactionally during reveal.
2. Include the winner's satisfied lifetime/streak achievement identifiers in the revealed result without exposing exact counters, and derive local Game Center reports from that snapshot.
3. Keep the Swift identifier list, `.gamekit` definitions, four localizations, image records, and Game Activity associations in exact parity.
4. Test positive picks plus explicit zero and negative rejection, cumulative threshold catch-up, 8/16 participant thresholds, cross-table streak continuation, participated-loss/no-winner resets, absence behavior, duplicate reveal handling, and reporting retries.
5. Validate JSON, referenced artwork, the installed Xcode GameKit model decoder, Swift tests, Go race tests, protobuf lint/build, and repository hooks.
6. As a separate release step, replace placeholder art, push the `.gamekit` configuration to App Store Connect, submit it for review, and verify it with Game Progress Manager and a physical Game Center account. Do not infer public availability from local validation alone.
