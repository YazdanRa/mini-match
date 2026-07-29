import Foundation
import Observation

@MainActor
@Observable
final class GameModel {
    enum Screen: Equatable {
        case home
        case lobby
        case result
    }

    private let client: any GameClient

    private(set) var screen: Screen = .home
    private(set) var table: GameTable?
    private(set) var currentPlayerID: String?
    private(set) var myLockedPick: UInt64?
    private(set) var result: ResultPresentation?
    private(set) var isWorking = false
    private(set) var isReconnecting = false
    private(set) var errorMessage = ""
    var isShowingError = false
    private(set) var multiplayerIsRestricted = false
    var pickText = "2"
    private var lastPresentedRound: UInt32?

    init(client: any GameClient) {
        self.client = client
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

    @discardableResult
    func createTable(name: String, displayName: String, avatarID: String = "spark") async -> Bool {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return false
        }
        guard let name = nonempty(name), let displayName = nonempty(displayName) else {
            showError(String(localized: "Enter a table name and your name."))
            return false
        }
        return await loadSession {
            try await client.createTable(name: name, displayName: displayName, avatarID: avatarID)
        }
    }

    @discardableResult
    func joinTable(code: String, displayName: String, avatarID: String = "spark") async -> Bool {
        guard !multiplayerIsRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return false
        }
        guard let code = nonempty(code), let displayName = nonempty(displayName) else {
            showError(String(localized: "Enter a table code and your name."))
            return false
        }
        return await loadSession {
            try await client.joinTable(
                code: code.uppercased(),
                displayName: displayName,
                avatarID: avatarID
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

        await perform {
            let updated = try await client.lockPick(
                tableID: table.id,
                playerID: currentPlayerID,
                roundNumber: roundNumber,
                pick: pick
            )
            guard self.table?.id == table.id else { return }
            apply(updated)
            myLockedPick = pick
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

        await perform {
            let updated = try await client.revealRound(
                tableID: table.id,
                hostPlayerID: currentPlayerID,
                roundNumber: roundNumber
            )
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
        do {
            apply(try await client.getTable(id: table.id))
            isReconnecting = false
        } catch is CancellationError {
            return
        } catch {
            isReconnecting = true
        }
    }

    func setMultiplayerRestricted(_ restricted: Bool) async {
        multiplayerIsRestricted = restricted
        if restricted, screen != .home {
            await leaveTable()
        }
    }

    func nextRound() {
        guard table?.state == .active else {
            resetSession()
            return
        }
        result = nil
        myLockedPick = nil
        pickText = ""
        screen = .lobby
    }

    func leaveTable() async {
        guard let table, let currentPlayerID else {
            resetSession()
            return
        }
        if table.state == .finished {
            resetSession()
            return
        }
        await perform {
            try await client.leaveTable(tableID: table.id, playerID: currentPlayerID)
            guard self.table?.id == table.id else { return }
            resetSession()
        }
    }

    private func resetSession() {
        table = nil
        currentPlayerID = nil
        myLockedPick = nil
        result = nil
        lastPresentedRound = nil
        isReconnecting = false
        pickText = "2"
        screen = .home
    }

    private func loadSession(_ operation: () async throws -> GameSession) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await operation()
            table = session.table
            currentPlayerID = session.playerID
            myLockedPick = nil
            result = nil
            lastPresentedRound = session.table.lastResult?.roundNumber
            pickText = "2"
            screen = .lobby
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        let sessionID = table?.id
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            if table?.id == sessionID {
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

    private func presentResult(from table: GameTable, for roundNumber: UInt32) {
        guard let lastResult = table.lastResult, lastResult.roundNumber == roundNumber else {
            return
        }
        result = ResultPresentation(table: table, result: lastResult)
        lastPresentedRound = roundNumber
        screen = .result
    }

    private func apply(_ updated: GameTable) {
        guard updated.id == table?.id, updated.stateVersion >= (table?.stateVersion ?? 0) else {
            return
        }
        table = updated
        guard let roundNumber = updated.lastResult?.roundNumber,
              roundNumber != lastPresentedRound
        else {
            return
        }
        presentResult(from: updated, for: roundNumber)
    }
}
