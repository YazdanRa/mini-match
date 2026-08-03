import Foundation
import Observation

struct SavedGameSession: Codable, Equatable {
    let tableID: String
    let playerID: String
    let gameCenterPlayerID: String?
}

@MainActor
protocol GameSessionPersisting: AnyObject {
    func load() -> SavedGameSession?
    func save(_ session: SavedGameSession)
    func clear()
}

@MainActor
final class UserDefaultsGameSessionStore: GameSessionPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "activeGameSession") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> SavedGameSession? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedGameSession.self, from: $0) }
    }

    func save(_ session: SavedGameSession) {
        defaults.set(try? JSONEncoder().encode(session), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class VolatileGameSessionStore: GameSessionPersisting {
    private var session: SavedGameSession?

    func load() -> SavedGameSession? { session }
    func save(_ session: SavedGameSession) { self.session = session }
    func clear() { session = nil }
}

@MainActor
@Observable
final class GameModel {
    enum Screen: Equatable {
        case home
        case lobby
    }

    private let client: any GameClient
    private let sessionStore: any GameSessionPersisting
    @ObservationIgnored var roundResultHandler: ((GameTable, String) -> Void)?
    @ObservationIgnored private var lastNotifiedResultID: String?
    @ObservationIgnored private var sessionGeneration = 0

    private(set) var screen: Screen = .home
    private(set) var table: GameTable?
    private(set) var currentPlayerID: String?
    private(set) var myLockedPick: UInt64?
    private(set) var isWorking = false
    private(set) var isReconnecting = false
    private(set) var errorMessage = ""
    var isShowingError = false
    private(set) var multiplayerIsRestricted = false
    var pickText = ""

    init(
        client: any GameClient,
        sessionStore: any GameSessionPersisting = UserDefaultsGameSessionStore()
    ) {
        self.client = client
        self.sessionStore = sessionStore
    }

    var isHost: Bool {
        table?.hostPlayerID == currentPlayerID
    }

    var currentPlayerIsLocked: Bool {
        guard let currentPlayerID else { return false }
        return table?.players.first { $0.id == currentPlayerID }?.isLocked == true
    }

    var canReveal: Bool {
        isHost && table?.allPlayersLocked == true
    }

    var canStartRound: Bool {
        isHost && table?.currentRound == nil && (table?.players.count ?? 0) >= 2
    }

    var canLockPick: Bool {
        UInt64(pickText) != nil
    }

    var result: ResultPresentation? {
        guard let table, table.currentRound == nil, let lastResult = table.lastResult else {
            return nil
        }
        return ResultPresentation(table: table, result: lastResult)
    }

    @discardableResult
    func createTable(
        name: String,
        displayName: String,
        avatarID: String = "spark",
        gameCenterIdentity: GameCenterIdentityDTO? = nil,
        joinCode: String? = nil
    ) async -> Bool {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return false
        }
        guard let name = nonempty(name), let displayName = nonempty(displayName) else {
            showError(String(localized: "Enter a table name and your name."))
            return false
        }
        return await loadSession(gameCenterPlayerID: gameCenterIdentity?.teamPlayerId) {
            try await client.createTable(
                name: name,
                displayName: displayName,
                avatarID: avatarID,
                gameCenterIdentity: gameCenterIdentity,
                joinCode: joinCode
            )
        }
    }

    @discardableResult
    func enterActivity(
        code: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?
    ) async -> Bool {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return false
        }
        return await loadSession(gameCenterPlayerID: gameCenterIdentity?.teamPlayerId) {
            do {
                return try await client.joinTable(
                    code: code,
                    displayName: displayName,
                    avatarID: avatarID,
                    gameCenterIdentity: gameCenterIdentity
                )
            } catch GameClientError.notFound {
                do {
                    return try await client.createTable(
                        name: "Mini Match",
                        displayName: displayName,
                        avatarID: avatarID,
                        gameCenterIdentity: gameCenterIdentity,
                        joinCode: code
                    )
                } catch GameClientError.alreadyExists {
                    return try await client.joinTable(
                        code: code,
                        displayName: displayName,
                        avatarID: avatarID,
                        gameCenterIdentity: gameCenterIdentity
                    )
                }
            }
        }
    }

    @discardableResult
    func joinTable(
        code: String,
        displayName: String,
        avatarID: String = "spark",
        gameCenterIdentity: GameCenterIdentityDTO? = nil
    ) async -> Bool {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return false
        }
        guard let code = nonempty(code), let displayName = nonempty(displayName) else {
            showError(String(localized: "Enter a table code and your name."))
            return false
        }
        return await loadSession(gameCenterPlayerID: gameCenterIdentity?.teamPlayerId) {
            try await client.joinTable(
                code: code.uppercased(),
                displayName: displayName,
                avatarID: avatarID,
                gameCenterIdentity: gameCenterIdentity
            )
        }
    }

    func lockPick() async {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return
        }
        guard let table,
              let currentPlayerID,
              let roundNumber = table.currentRound?.number,
              let pick = UInt64(pickText)
        else {
            showError(String(localized: "Enter a non-negative whole number."))
            return
        }
        let generation = sessionGeneration

        await perform {
            let updated = try await client.lockPick(
                tableID: table.id,
                playerID: currentPlayerID,
                roundNumber: roundNumber,
                pick: pick
            )
            guard self.table?.id == table.id, sessionGeneration == generation else { return }
            apply(updated)
            myLockedPick = pick
        }
    }

    func startRound() async {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return
        }
        guard let table, let currentPlayerID else {
            showError(String(localized: "The table is not ready."))
            return
        }
        let generation = sessionGeneration

        await perform {
            let updated = try await client.startRound(
                tableID: table.id,
                hostPlayerID: currentPlayerID
            )
            guard self.table?.id == table.id, sessionGeneration == generation else { return }
            apply(updated)
        }
    }

    func revealRound() async {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return
        }
        guard let table,
              let currentPlayerID,
              let roundNumber = table.currentRound?.number
        else {
            showError(String(localized: "The table is not ready."))
            return
        }
        let generation = sessionGeneration

        await perform {
            let updated = try await client.revealRound(
                tableID: table.id,
                hostPlayerID: currentPlayerID,
                roundNumber: roundNumber
            )
            guard self.table?.id == table.id, sessionGeneration == generation else { return }
            apply(updated)
        }
    }

    func observeTable() async {
        while !Task.isCancelled {
            await refreshTable()
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    func refreshTable() async {
        guard let table else { return }
        let tableID = table.id
        let generation = sessionGeneration
        do {
            let updated = try await client.getTable(id: table.id)
            guard self.table?.id == tableID, sessionGeneration == generation else { return }
            apply(updated)
            isReconnecting = false
        } catch is CancellationError {
            return
        } catch let error as GameClientError where error.endsTableSession {
            guard self.table?.id == tableID, sessionGeneration == generation else { return }
            resetSession()
            showError(error.localizedDescription)
        } catch {
            guard self.table?.id == tableID, sessionGeneration == generation else { return }
            isReconnecting = true
        }
    }

    @discardableResult
    func restoreSession(
        gameCenterPlayerID: String? = nil,
        identityIsCurrent: () -> Bool = { true }
    ) async -> Bool {
        guard screen == .home, !multiplayerIsRestricted, !isWorking,
              let saved = sessionStore.load()
        else {
            return false
        }
        if let savedPlayerID = saved.gameCenterPlayerID,
           savedPlayerID != gameCenterPlayerID {
            sessionStore.clear()
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let restored = try await client.getTable(id: saved.tableID)
            guard screen == .home, !multiplayerIsRestricted, sessionStore.load() == saved,
                  identityIsCurrent()
            else {
                sessionStore.clear()
                return false
            }
            guard restored.players.contains(where: { $0.id == saved.playerID }) else {
                sessionStore.clear()
                return false
            }
            sessionGeneration += 1
            table = restored
            currentPlayerID = saved.playerID
            myLockedPick = nil
            pickText = ""
            isReconnecting = false
            screen = .lobby
            notifyRoundResult()
            return true
        } catch is CancellationError {
            return false
        } catch let error as GameClientError where error.endsTableSession {
            sessionStore.clear()
            return false
        } catch {
            isReconnecting = true
            return false
        }
    }

    func setMultiplayerRestricted(_ restricted: Bool) async {
        multiplayerIsRestricted = restricted
        if restricted, screen != .home {
            await leaveTable()
            if screen != .home {
                resetSession()
            }
        }
    }

    func leaveTable() async {
        guard let table, let currentPlayerID else {
            resetSession()
            return
        }
        let tableID = table.id
        let generation = sessionGeneration
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.leaveTable(tableID: table.id, playerID: currentPlayerID)
            guard self.table?.id == table.id, sessionGeneration == generation else { return }
            resetSession()
        } catch let error as GameClientError where error.endsTableSession {
            guard self.table?.id == tableID, sessionGeneration == generation else { return }
            resetSession()
        } catch {
            guard self.table?.id == tableID, sessionGeneration == generation else { return }
            showError(error.localizedDescription)
        }
    }

    func discardSession() {
        resetSession()
    }

    private func resetSession() {
        sessionGeneration += 1
        table = nil
        currentPlayerID = nil
        myLockedPick = nil
        isReconnecting = false
        pickText = ""
        screen = .home
        sessionStore.clear()
    }

    private func loadSession(
        gameCenterPlayerID: String?,
        _ operation: () async throws -> GameSession
    ) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await operation()
            sessionGeneration += 1
            table = session.table
            currentPlayerID = session.playerID
            sessionStore.save(SavedGameSession(
                tableID: session.table.id,
                playerID: session.playerID,
                gameCenterPlayerID: gameCenterPlayerID
            ))
            myLockedPick = nil
            pickText = ""
            screen = .lobby
            notifyRoundResult()
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        let sessionID = table?.id
        let generation = sessionGeneration
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            if table?.id == sessionID, sessionGeneration == generation {
                showError(error.localizedDescription)
            }
        }
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func apply(_ updated: GameTable) {
        guard updated.id == table?.id, updated.stateVersion >= (table?.stateVersion ?? 0) else {
            return
        }
        let previousRoundNumber = table?.currentRound?.number
        table = updated
        notifyRoundResult()
        if updated.currentRound?.number != previousRoundNumber {
            myLockedPick = nil
            pickText = ""
        }
    }

    private func notifyRoundResult() {
        guard let table, table.currentRound == nil, let result = table.lastResult,
              let currentPlayerID, let roundResultHandler
        else {
            return
        }
        let resultID = "\(table.id):\(result.roundNumber)"
        guard resultID != lastNotifiedResultID else { return }
        lastNotifiedResultID = resultID
        roundResultHandler(table, currentPlayerID)
    }
}

extension GameModel {
    static func preview(table: GameTable? = nil) -> GameModel {
        let model = GameModel(
            client: PreviewGameClient(
                table: table,
                localPick: table?.allPlayersLocked == true ? 2 : nil
            ),
            sessionStore: VolatileGameSessionStore()
        )
        guard let table else { return model }

        model.table = table
        model.currentPlayerID = PreviewFixtures.currentPlayerID
        model.screen = .lobby
        return model
    }
}
