import Foundation
import FirebaseAuth

struct ConnectGameClient: GameClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func createTable(
        name: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?
    ) async throws -> GameSession {
        let response: SessionResponse = try await call(
            "CreateTable",
            body: CreateTableRequest(
                name: name,
                hostDisplayName: displayName,
                hostAvatar: avatarID,
                gameCenterIdentity: gameCenterIdentity
            )
        )
        return GameSession(table: try response.table.model(), playerID: response.playerId)
    }

    func joinTable(
        code: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?
    ) async throws -> GameSession {
        let response: SessionResponse = try await call(
            "JoinTable",
            body: JoinTableRequest(
                joinCode: code,
                displayName: displayName,
                avatar: avatarID,
                gameCenterIdentity: gameCenterIdentity
            )
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
            "RevealRound",
            body: RevealRoundRequest(
                tableId: tableID,
                hostPlayerId: hostPlayerID,
                roundNumber: roundNumber
            )
        )
        return try response.table.model()
    }

    func startRound(tableID: String, hostPlayerID: String) async throws -> GameTable {
        let response: TableResponse = try await call(
            "BeginRound",
            body: BeginRoundRequest(tableId: tableID, hostPlayerId: hostPlayerID)
        )
        return try response.table.model()
    }

    func getTable(id: String) async throws -> GameTable {
        let response: TableResponse = try await call("GetTable", body: GetTableRequest(tableId: id))
        return try response.table.model()
    }

    func deleteProfile() async throws {
        let _: EmptyResponse = try await call("DeleteProfile", body: EmptyRequest())
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
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).localizedMessage)
                ?? String(localized: "The request failed.")
            throw GameClientError.server(message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
