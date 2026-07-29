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
    private(set) var errorMessage = ""
    var isShowingError = false
    var pickText = "2"

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
    func createTable(name: String, displayName: String) async -> Bool {
        guard let name = nonempty(name), let displayName = nonempty(displayName) else {
            showError(String(localized: "Enter a table name and your name."))
            return false
        }
        return await loadSession {
            try await client.createTable(name: name, displayName: displayName)
        }
    }

    @discardableResult
    func joinTable(code: String, displayName: String) async -> Bool {
        guard let code = nonempty(code), let displayName = nonempty(displayName) else {
            showError(String(localized: "Enter a table code and your name."))
            return false
        }
        return await loadSession {
            try await client.joinTable(code: code.uppercased(), displayName: displayName)
        }
    }

    func lockPick() async {
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
            self.table = updated
            myLockedPick = pick
            presentResult(from: updated, for: roundNumber)
        }
    }

    func revealRound() async {
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
            self.table = updated
            presentResult(from: updated, for: roundNumber)
        }
    }

    func nextRound() {
        guard table?.state == .active else {
            leaveTable()
            return
        }
        result = nil
        myLockedPick = nil
        pickText = ""
        screen = .lobby
    }

    func leaveTable() {
        table = nil
        currentPlayerID = nil
        myLockedPick = nil
        result = nil
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
            pickText = "2"
            screen = .lobby
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            showError(error.localizedDescription)
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
        screen = .result
    }
}
