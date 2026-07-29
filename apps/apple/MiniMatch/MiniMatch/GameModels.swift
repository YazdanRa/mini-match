import Foundation

struct GameSession: Equatable, Sendable {
    let table: GameTable
    let playerID: String
}

struct GameTable: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case active
        case finished
    }

    let id: String
    let name: String
    let joinCode: String
    let hostPlayerID: String
    var players: [GamePlayer]
    var state: State
    var currentRound: GameRound?
    var lastResult: GameRoundResult?
    let winsToFinish: UInt32
    var stateVersion: UInt64
    var eventSequence: UInt64
    var winnerPlayerID: String?

    var allPlayersLocked: Bool {
        !players.isEmpty && players.allSatisfy(\.isLocked)
    }
}

struct GamePlayer: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    var wins: UInt32
    var isLocked: Bool
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
}

struct GameSelection: Identifiable, Equatable, Sendable {
    var id: String { playerID }

    let playerID: String
    let pick: UInt64
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

        winnerName = result.winnerPlayerID.flatMap { names[$0] }
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
                displayName: names[selection.playerID, default: String(localized: "Player")],
                pick: selection.pick,
                status: status
            )
        }
    }
}
