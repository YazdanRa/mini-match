import Foundation
import FirebaseAuth

struct ConnectGameClient: GameClient {
    private let baseURL: URL
    private let authorizationToken: @Sendable () async throws -> String
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        authorizationToken = Self.firebaseAuthorizationToken
        send = { try await session.data(for: $0) }
    }

    init(
        baseURL: URL,
        authorizationToken: @escaping @Sendable () async throws -> String,
        send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.baseURL = baseURL
        self.authorizationToken = authorizationToken
        self.send = send
    }

    func createTable(
        name: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?,
        joinCode: String?
    ) async throws -> GameSession {
        let response: SessionResponse = try await call(
            "CreateTable",
            body: CreateTableRequest(
                name: name,
                hostDisplayName: displayName,
                hostAvatar: avatarID,
                gameCenterIdentity: gameCenterIdentity,
                joinCode: joinCode
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
        let _: EmptyResponse = try await call(
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
        let idToken = try await authorizationToken()
        let servicePath = "minimatch.v1.MiniMatchService/\(method)"
        var request = URLRequest(url: baseURL.appending(path: servicePath))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GameClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                switch error.code {
                case "not_found":
                    throw GameClientError.notFound
                case "already_exists":
                    throw GameClientError.alreadyExists
                case "permission_denied":
                    throw GameClientError.permissionDenied
                case "unauthenticated":
                    throw GameClientError.unauthenticated
                default:
                    throw GameClientError.server(error.localizedMessage)
                }
            }
            let message = String(localized: "The request failed.")
            throw GameClientError.server(message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func firebaseAuthorizationToken() async throws -> String {
        let user = if let currentUser = Auth.auth().currentUser {
            currentUser
        } else {
            try await Auth.auth().signInAnonymously().user
        }
        return try await user.getIDToken()
    }
}
