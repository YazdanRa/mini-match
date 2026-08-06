import Foundation

enum PlayerAvatar: String, CaseIterable, Identifiable, Sendable {
    case spark
    case fox
    case owl
    case cat
    case dog
    case frog

    var id: Self { self }

    var glyph: String {
        switch self {
        case .spark: "✨"
        case .fox: "🦊"
        case .owl: "🦉"
        case .cat: "🐱"
        case .dog: "🐶"
        case .frog: "🐸"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .spark: "Spark"
        case .fox: "Fox"
        case .owl: "Owl"
        case .cat: "Cat"
        case .dog: "Dog"
        case .frog: "Frog"
        }
    }
}

struct GameSession: Equatable, Sendable {
    let table: GameTable
    let playerID: String
}

struct GameTable: Equatable, Sendable {
    let id: String
    let name: String
    let joinCode: String
    let hostPlayerID: String
    var players: [GamePlayer]
    var currentRound: GameRound?
    var lastResult: GameRoundResult?
    var stateVersion: UInt64
    var eventSequence: UInt64

    var allPlayersLocked: Bool {
        players.count >= 2 && players.allSatisfy(\.isLocked)
    }
}

struct GamePlayer: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let avatarID: String
    var isLocked: Bool
    var wins: UInt32 = 0

    var avatarGlyph: String {
        PlayerAvatar(rawValue: avatarID)?.glyph ?? PlayerAvatar.spark.glyph
    }
}

struct GameRound: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case acceptingPicks
        case readyToReveal
    }

    let number: UInt32
    let phase: Phase
}

struct GameRoundResult: Equatable, Sendable {
    let roundNumber: UInt32
    let selections: [GameSelection]
    let winnerPlayerID: String?
    let winnerAchievementIDs: Set<String>
    let localPlayerLeaderboardScore: UInt64?

    init(
        roundNumber: UInt32,
        selections: [GameSelection],
        winnerPlayerID: String?,
        winnerAchievementIDs: Set<String> = [],
        localPlayerLeaderboardScore: UInt64? = nil
    ) {
        self.roundNumber = roundNumber
        self.selections = selections
        self.winnerPlayerID = winnerPlayerID
        self.winnerAchievementIDs = winnerAchievementIDs
        self.localPlayerLeaderboardScore = localPlayerLeaderboardScore
    }
}

struct GameSelection: Identifiable, Equatable, Sendable {
    var id: String { playerID }

    let playerID: String
    let displayName: String
    let pick: UInt64
    var wins: UInt32? = nil
}

struct ResultPresentation: Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case winner
            case duplicate
            case unique
        }

        var id: String { playerID }

        let playerID: String
        let displayName: String
        let pick: UInt64
        let wins: UInt32?
        let status: Status
    }

    let winnerName: String?
    let winningPick: UInt64?
    let rows: [Row]

    init(table: GameTable, result: GameRoundResult) {
        let pickCounts = result.selections.reduce(into: [UInt64: Int]()) {
            $0[$1.pick, default: 0] += 1
        }
        let names = Dictionary(uniqueKeysWithValues: table.players.map { ($0.id, $0.displayName) })
        let wins = Dictionary(uniqueKeysWithValues: table.players.map { ($0.id, $0.wins) })

        let resultNames = Dictionary(uniqueKeysWithValues: result.selections.compactMap {
            $0.displayName.isEmpty ? nil : ($0.playerID, $0.displayName)
        })

        winnerName = result.winnerPlayerID.map {
            resultNames[$0] ?? names[$0] ?? String(localized: "Player")
        }
        winningPick = result.selections.first { $0.playerID == result.winnerPlayerID }?.pick
        rows = result.selections.map { selection in
            let status: Row.Status
            if selection.playerID == result.winnerPlayerID {
                status = .winner
            } else if pickCounts[selection.pick, default: 0] > 1 {
                status = .duplicate
            } else {
                status = .unique
            }
            return Row(
                playerID: selection.playerID,
                displayName: selection.displayName.isEmpty
                    ? names[selection.playerID, default: String(localized: "Player")]
                    : selection.displayName,
                pick: selection.pick,
                wins: selection.wins ?? wins[selection.playerID],
                status: status
            )
        }
    }

    var accessibilitySummary: String {
        if let winnerName, let winningPick {
            return String(localized: "\(winnerName) wins with \(winningPick)")
        }
        return String(localized: "No winner. Every number was duplicated.")
    }
}
