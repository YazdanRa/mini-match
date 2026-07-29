import Foundation
import FirebaseAuth

protocol GameClient: Sendable {
    func createTable(name: String, displayName: String, avatarID: String) async throws -> GameSession
    func joinTable(code: String, displayName: String, avatarID: String) async throws -> GameSession
    func leaveTable(tableID: String, playerID: String) async throws
    func lockPick(
        tableID: String,
        playerID: String,
        roundNumber: UInt32,
        pick: UInt64
    ) async throws -> GameTable
    func revealRound(
        tableID: String,
        hostPlayerID: String,
        roundNumber: UInt32
    ) async throws -> GameTable
    func getTable(id: String) async throws -> GameTable
}

enum GameClientError: Error, LocalizedError, Sendable {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "The server returned an invalid response.")
        case let .server(message):
            message
        }
    }
}

struct ConnectGameClient: GameClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func createTable(name: String, displayName: String, avatarID: String) async throws -> GameSession {
        let response: SessionResponse = try await call(
            "CreateTable",
            body: CreateTableRequest(
                name: name,
                hostDisplayName: displayName,
                hostAvatar: avatarID
            )
        )
        return GameSession(table: try response.table.model(), playerID: response.playerId)
    }

    func joinTable(code: String, displayName: String, avatarID: String) async throws -> GameSession {
        let response: SessionResponse = try await call(
            "JoinTable",
            body: JoinTableRequest(joinCode: code, displayName: displayName, avatar: avatarID)
        )
        return GameSession(table: try response.table.model(), playerID: response.playerId)
    }

    func leaveTable(tableID: String, playerID: String) async throws {
        let _: TableResponse = try await call(
            "LeaveTable",
            body: LeaveTableRequest(tableId: tableID, playerId: playerID)
        )
    }

    func lockPick(
        tableID: String,
        playerID: String,
        roundNumber: UInt32,
        pick: UInt64
    ) async throws -> GameTable {
        let response: TableResponse = try await call(
            "LockPick",
            body: LockPickRequest(
                tableId: tableID,
                playerId: playerID,
                pick: PickDTO(value: String(pick)),
                roundNumber: roundNumber
            )
        )
        return try response.table.model()
    }

    func revealRound(
        tableID: String,
        hostPlayerID: String,
        roundNumber: UInt32
    ) async throws -> GameTable {
        let response: TableResponse = try await call(
            "StartRound",
            body: StartRoundRequest(
                tableId: tableID,
                hostPlayerId: hostPlayerID,
                roundNumber: roundNumber
            )
        )
        return try response.table.model()
    }

    func getTable(id: String) async throws -> GameTable {
        let response: TableResponse = try await call("GetTable", body: GetTableRequest(tableId: id))
        return try response.table.model()
    }

    private func call<Request: Encodable, Response: Decodable>(
        _ method: String,
        body: Request
    ) async throws -> Response {
        let user = if let currentUser = Auth.auth().currentUser {
            currentUser
        } else {
            try await Auth.auth().signInAnonymously().user
        }
        let idToken = try await user.getIDToken()
        let servicePath = "minimatch.v1.MiniMatchService/\(method)"
        var request = URLRequest(url: baseURL.appending(path: servicePath))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GameClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)
                ?? String(localized: "The request failed.")
            throw GameClientError.server(message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

actor PreviewGameClient: GameClient {
    private var table: GameTable?
    private var currentPlayerID = "local-player"
    private var localPick: UInt64?

    func createTable(name: String, displayName: String, avatarID: String) async throws -> GameSession {
        currentPlayerID = "local-player"
        let created = sampleTable(
            name: name,
            hostID: currentPlayerID,
            hostName: displayName,
            hostAvatarID: avatarID
        )
        table = created
        return GameSession(table: created, playerID: currentPlayerID)
    }

    func joinTable(code: String, displayName: String, avatarID: String) async throws -> GameSession {
        currentPlayerID = "local-player"
        var joined = sampleTable(
            name: "Friday Mini Match",
            hostID: "casey",
            hostName: "Casey",
            hostAvatarID: "fox"
        )
        joined = withPlayer(
            GamePlayer(
                id: currentPlayerID,
                displayName: displayName,
                avatarID: avatarID,
                wins: 0,
                isLocked: false
            ),
            addedTo: joined
        )
        joined = withJoinCode(code, in: joined)
        table = joined
        return GameSession(table: joined, playerID: currentPlayerID)
    }

    func leaveTable(tableID: String, playerID: String) async throws {
        guard var table, table.id == tableID else {
            throw GameClientError.server(String(localized: "Table not found."))
        }
        table.players.removeAll { $0.id == playerID }
        if table.hostPlayerID == playerID, let nextHost = table.players.first {
            table = withHost(nextHost.id, in: table)
        }
        table.stateVersion += 1
        table.eventSequence += 1
        self.table = table
    }

    func lockPick(
        tableID: String,
        playerID: String,
        roundNumber: UInt32,
        pick: UInt64
    ) async throws -> GameTable {
        guard var table, table.id == tableID, table.currentRound?.number == roundNumber else {
            throw GameClientError.server(String(localized: "That round is no longer active."))
        }
        guard table.players.contains(where: { $0.id == playerID && !$0.isLocked }) else {
            throw GameClientError.server(String(localized: "This player has already locked a number."))
        }

        localPick = pick
        // ponytail: preview-only auto-lock keeps the local flow playable until Firestore supplies remote updates.
        for index in table.players.indices {
            table.players[index].isLocked = true
        }
        table.currentRound = GameRound(number: roundNumber, phase: .readyToReveal)
        table.stateVersion += 1
        table.eventSequence += 1
        self.table = table
        if playerID != table.hostPlayerID {
            return try await revealRound(
                tableID: tableID,
                hostPlayerID: table.hostPlayerID,
                roundNumber: roundNumber
            )
        }
        return table
    }

    func revealRound(
        tableID: String,
        hostPlayerID: String,
        roundNumber: UInt32
    ) async throws -> GameTable {
        guard var table,
              table.id == tableID,
              table.hostPlayerID == hostPlayerID,
              table.currentRound?.number == roundNumber,
              table.allPlayersLocked,
              let localPick
        else {
            throw GameClientError.server(String(localized: "The round is not ready to reveal."))
        }

        let winnerID = "liam"
        let winnerPick = localPick <= UInt64.max - 3 ? localPick + 3 : 0
        let selections = table.players.map { player in
            GameSelection(
                playerID: player.id,
                pick: player.id == winnerID ? winnerPick : localPick
            )
        }
        table.lastResult = GameRoundResult(
            roundNumber: roundNumber,
            selections: selections,
            winnerPlayerID: winnerID
        )
        for index in table.players.indices {
            table.players[index].isLocked = false
            if table.players[index].id == winnerID {
                table.players[index].wins += 1
            }
        }
        if table.players.first(where: { $0.id == winnerID })?.wins == table.winsToFinish {
            table.state = .finished
            table.currentRound = nil
            table.winnerPlayerID = winnerID
        } else {
            table.currentRound = GameRound(number: roundNumber + 1, phase: .acceptingPicks)
        }
        table.stateVersion += 1
        table.eventSequence += 1
        self.table = table
        return table
    }

    func getTable(id: String) async throws -> GameTable {
        guard let table, table.id == id else {
            throw GameClientError.server(String(localized: "Table not found."))
        }
        return table
    }

    private func sampleTable(
        name: String,
        hostID: String,
        hostName: String,
        hostAvatarID: String
    ) -> GameTable {
        GameTable(
            id: "preview-table",
            name: name,
            joinCode: "7X2G9K",
            hostPlayerID: hostID,
            players: [
                GamePlayer(
                    id: hostID,
                    displayName: hostName,
                    avatarID: hostAvatarID,
                    wins: 0,
                    isLocked: false
                ),
                GamePlayer(id: "zoe", displayName: "Zoe", avatarID: "owl", wins: 0, isLocked: false),
                GamePlayer(id: "liam", displayName: "Liam", avatarID: "frog", wins: 0, isLocked: false),
            ],
            state: .active,
            currentRound: GameRound(number: 1, phase: .acceptingPicks),
            lastResult: nil,
            winsToFinish: 5,
            stateVersion: 1,
            eventSequence: 1,
            winnerPlayerID: nil
        )
    }

    private func withPlayer(_ player: GamePlayer, addedTo table: GameTable) -> GameTable {
        var updated = table
        updated.players.append(player)
        return updated
    }

    private func withJoinCode(_ code: String, in table: GameTable) -> GameTable {
        GameTable(
            id: table.id,
            name: table.name,
            joinCode: code.uppercased(),
            hostPlayerID: table.hostPlayerID,
            players: table.players,
            state: table.state,
            currentRound: table.currentRound,
            lastResult: table.lastResult,
            winsToFinish: table.winsToFinish,
            stateVersion: table.stateVersion,
            eventSequence: table.eventSequence,
            winnerPlayerID: table.winnerPlayerID
        )
    }

    private func withHost(_ hostID: String, in table: GameTable) -> GameTable {
        GameTable(
            id: table.id,
            name: table.name,
            joinCode: table.joinCode,
            hostPlayerID: hostID,
            players: table.players,
            state: table.state,
            currentRound: table.currentRound,
            lastResult: table.lastResult,
            winsToFinish: table.winsToFinish,
            stateVersion: table.stateVersion,
            eventSequence: table.eventSequence,
            winnerPlayerID: table.winnerPlayerID
        )
    }
}

enum GameClientFactory {
    static func make() -> any GameClient {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-lobby") || arguments.contains("--preview-result") {
            return PreviewGameClient()
        }
        return ConnectGameClient(
            baseURL: URL(
                string: "https://mini-match-api-704518244082.northamerica-northeast2.run.app"
            )!
        )
    }
}

private struct CreateTableRequest: Encodable {
    let name: String
    let hostDisplayName: String
    let hostAvatar: String
}

private struct JoinTableRequest: Encodable {
    let joinCode: String
    let displayName: String
    let avatar: String
}

private struct LockPickRequest: Encodable {
    let tableId: String
    let playerId: String
    let pick: PickDTO
    let roundNumber: UInt32
}

private struct LeaveTableRequest: Encodable {
    let tableId: String
    let playerId: String
}

private struct StartRoundRequest: Encodable {
    let tableId: String
    let hostPlayerId: String
    let roundNumber: UInt32
}

private struct GetTableRequest: Encodable {
    let tableId: String
}

private struct SessionResponse: Decodable {
    let table: TableDTO
    let playerId: String
}

private struct TableResponse: Decodable {
    let table: TableDTO
}

private struct ErrorResponse: Decodable {
    let message: String
}

struct TableDTO: Decodable {
    let id: String
    let name: String
    let joinCode: String
    let hostPlayerId: String
    let players: [PlayerDTO]
    let state: String?
    let currentRound: RoundDTO?
    let lastResult: ResultDTO?
    let winsToFinish: UInt32
    let stateVersion: String?
    let eventSequence: String?
    let winnerPlayerId: String?

    func model() throws -> GameTable {
        let tableState: GameTable.State
        switch state {
        case "TABLE_STATE_ACTIVE":
            tableState = .active
        case "TABLE_STATE_FINISHED":
            tableState = .finished
        default:
            throw GameClientError.invalidResponse
        }

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
            state: tableState,
            currentRound: try currentRound?.model(),
            lastResult: try lastResult?.model(),
            winsToFinish: winsToFinish,
            stateVersion: stateVersion,
            eventSequence: eventSequence,
            winnerPlayerID: winnerPlayerId
        )
    }
}

struct PlayerDTO: Decodable {
    let id: String
    let displayName: String
    let avatar: String?
    let wins: UInt32?
    let locked: Bool?

    var model: GamePlayer {
        GamePlayer(
            id: id,
            displayName: displayName,
            avatarID: avatar ?? PlayerAvatar.spark.rawValue,
            wins: wins ?? 0,
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
    let pick: PickDTO

    func model() throws -> GameSelection {
        guard let value = UInt64(pick.value ?? "0") else {
            throw GameClientError.invalidResponse
        }
        return GameSelection(playerID: playerId, pick: value)
    }
}

struct PickDTO: Codable {
    let value: String?

    init(value: String) {
        self.value = value
    }
}
