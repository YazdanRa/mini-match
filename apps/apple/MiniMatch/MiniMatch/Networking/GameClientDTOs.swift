import Foundation

struct CreateTableRequest: Encodable {
    let name: String
    let hostDisplayName: String
    let hostAvatar: String
    let gameCenterIdentity: GameCenterIdentityDTO?
    let joinCode: String?
}

struct JoinTableRequest: Encodable {
    let joinCode: String
    let displayName: String
    let avatar: String
    let gameCenterIdentity: GameCenterIdentityDTO?
}

struct GameCenterIdentityDTO: Encodable, Sendable {
    let teamPlayerId: String
    let publicKeyUrl: String
    let signature: Data
    let salt: Data
    let timestamp: String
}

struct LockPickRequest: Encodable {
    let tableId: String
    let playerId: String
    let pick: PickDTO
    let roundNumber: UInt32
}

struct LeaveTableRequest: Encodable {
    let tableId: String
    let playerId: String
}

struct BeginRoundRequest: Encodable {
    let tableId: String
    let hostPlayerId: String
}

struct RevealRoundRequest: Encodable {
    let tableId: String
    let hostPlayerId: String
    let roundNumber: UInt32
}

struct GetTableRequest: Encodable {
    let tableId: String
}

struct EmptyRequest: Encodable {}

struct EmptyResponse: Decodable {}

struct SessionResponse: Decodable {
    let table: TableDTO
    let playerId: String
}

struct TableResponse: Decodable {
    let table: TableDTO
}

struct ErrorResponse: Decodable {
    let code: String

    var localizedMessage: String {
        switch code {
        case "invalid_argument":
            String(localized: "Check the table details and try again.")
        case "not_found":
            String(localized: "Table not found.")
        case "already_exists":
            String(localized: "That table already exists.")
        case "permission_denied":
            String(localized: "You don’t have permission to do that.")
        case "failed_precondition":
            String(localized: "The table is not ready.")
        case "unauthenticated":
            String(localized: "Sign in and try again.")
        case "resource_exhausted":
            String(localized: "Couldn’t create a table. Try again.")
        default:
            String(localized: "The request failed.")
        }
    }
}

struct TableDTO: Decodable {
    let id: String
    let name: String
    let joinCode: String
    let hostPlayerId: String
    let players: [PlayerDTO]
    let currentRound: RoundDTO?
    let lastResult: ResultDTO?
    let stateVersion: String?
    let eventSequence: String?

    func model() throws -> GameTable {
        guard let stateVersion = UInt64(stateVersion ?? "0"),
              let eventSequence = UInt64(eventSequence ?? "0")
        else {
            throw GameClientError.invalidResponse
        }
        return GameTable(
            id: id,
            name: name,
            joinCode: joinCode,
            hostPlayerID: hostPlayerId,
            players: players.map(\.model),
            currentRound: try currentRound?.model(),
            lastResult: try lastResult?.model(),
            stateVersion: stateVersion,
            eventSequence: eventSequence
        )
    }
}

struct PlayerDTO: Decodable {
    let id: String
    let displayName: String
    let avatar: String?
    let locked: Bool?

    var model: GamePlayer {
        GamePlayer(
            id: id,
            displayName: displayName,
            avatarID: avatar ?? PlayerAvatar.spark.rawValue,
            isLocked: locked ?? false
        )
    }
}

struct RoundDTO: Decodable {
    let number: UInt32
    let phase: String?

    func model() throws -> GameRound {
        let roundPhase: GameRound.Phase
        switch phase {
        case "ROUND_PHASE_ACCEPTING_PICKS":
            roundPhase = .acceptingPicks
        case "ROUND_PHASE_READY_TO_REVEAL":
            roundPhase = .readyToReveal
        default:
            throw GameClientError.invalidResponse
        }
        return GameRound(number: number, phase: roundPhase)
    }
}

struct ResultDTO: Decodable {
    let roundNumber: UInt32
    let selections: [SelectionDTO]
    let winnerPlayerId: String?

    func model() throws -> GameRoundResult {
        GameRoundResult(
            roundNumber: roundNumber,
            selections: try selections.map { try $0.model() },
            winnerPlayerID: winnerPlayerId
        )
    }
}

struct SelectionDTO: Decodable {
    let playerId: String
    let displayName: String?
    let pick: PickDTO

    func model() throws -> GameSelection {
        guard let value = UInt64(pick.value ?? "0") else {
            throw GameClientError.invalidResponse
        }
        return GameSelection(playerID: playerId, displayName: displayName ?? "", pick: value)
    }
}

struct PickDTO: Codable {
    let value: String?

    init(value: String) {
        self.value = value
    }
}
