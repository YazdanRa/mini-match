import Foundation

protocol GameClient: Sendable {
    func createTable(
        name: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?
    ) async throws -> GameSession
    func joinTable(
        code: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?
    ) async throws -> GameSession
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
    func deleteProfile() async throws
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
