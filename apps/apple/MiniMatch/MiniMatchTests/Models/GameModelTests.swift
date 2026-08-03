import Foundation
import Testing
@testable import MiniMatch

struct GameModelTests {
    @Test
    func serverConfirmedWinsEarnTheExpectedGameCenterAchievements() {
        var table = PreviewFixtures.lobbyTable
        table.lastResult = GameRoundResult(
            roundNumber: 1,
            selections: [
                GameSelection(playerID: PreviewFixtures.currentPlayerID, displayName: "Maya", pick: 0),
                GameSelection(playerID: "zoe", displayName: "Zoe", pick: 1),
                GameSelection(playerID: "liam", displayName: "Liam", pick: 2),
                GameSelection(playerID: "noah", displayName: "Noah", pick: 3),
            ],
            winnerPlayerID: PreviewFixtures.currentPlayerID
        )

        #expect(GameCenterAchievement.earned(
            in: table,
            currentPlayerID: PreviewFixtures.currentPlayerID
        ) == [.firstWin, .zeroWin, .fourPlayerWin])

        table.lastResult = GameRoundResult(
            roundNumber: 2,
            selections: table.lastResult?.selections ?? [],
            winnerPlayerID: "zoe"
        )
        #expect(GameCenterAchievement.earned(
            in: table,
            currentPlayerID: PreviewFixtures.currentPlayerID
        ).isEmpty)
    }

    @Test
    @MainActor
    func pickStartsEmptyAndOnlyAcceptsUInt64Values() async {
        let model = GameModel(client: PreviewGameClient())

        #expect(model.pickText.isEmpty)
        #expect(!model.canLockPick)

        model.pickText = "18446744073709551616"
        #expect(!model.canLockPick)

        model.pickText = "0"
        #expect(model.canLockPick)

        #expect(await model.createTable(name: "Friday Mini Match", displayName: "Maya"))
        #expect(model.pickText.isEmpty)
        model.pickText = "2"
        model.discardSession()
        #expect(model.pickText.isEmpty)
    }

    @Test
    @MainActor
    func hostCanRevealOnlyAfterLocking() async throws {
        let model = GameModel(client: PreviewGameClient())

        #expect(await model.createTable(name: "Friday Mini Match", displayName: "Maya"))
        #expect(model.screen == .lobby)
        #expect(model.canStartRound)
        #expect(!model.canReveal)

        await model.startRound()
        #expect(model.table?.currentRound?.number == 1)

        model.pickText = "-1"
        await model.lockPick()
        #expect(model.isShowingError)
        #expect(!model.currentPlayerIsLocked)

        model.isShowingError = false
        model.pickText = "2"
        await model.lockPick()
        #expect(model.currentPlayerIsLocked)
        #expect(model.canReveal)
        #expect(model.result == nil)

        await model.revealRound()

        #expect(model.screen == .lobby)
        #expect(model.result?.winnerName == "Liam")
        #expect(model.result?.winningPick == 5)
        #expect(model.result?.rows.filter { $0.status == .duplicate }.count == 2)
        #expect(model.table?.currentRound == nil)
        #expect(model.canStartRound)

        await model.startRound()
        #expect(model.table?.currentRound?.number == 2)
        #expect(model.result == nil)
    }

    @Test
    @MainActor
    func joinedPlayerReceivesPreviewReveal() async {
        let client = PreviewGameClient()
        let model = GameModel(client: client)

        #expect(await model.joinTable(code: "7X2G9K", displayName: "Maya"))
        #expect(!model.isHost)
        let table = try! #require(model.table)
        _ = try! await client.startRound(tableID: table.id, hostPlayerID: table.hostPlayerID)
        await model.refreshTable()

        model.pickText = "2"
        await model.lockPick()

        #expect(model.screen == .lobby)
        #expect(model.table?.currentRound == nil)
        #expect(model.result?.winnerName == "Liam")
        #expect(model.result?.winningPick == 5)
    }

    @Test
    @MainActor
    func tableRefreshConvergesRemoteStateOnce() async throws {
        let client = PreviewGameClient()
        let model = GameModel(client: client)
        var reportedResults = 0
        model.roundResultHandler = { _, _ in reportedResults += 1 }

        #expect(await model.createTable(
            name: "Friday Mini Match",
            displayName: "Maya",
            avatarID: "fox"
        ))
        let table = try #require(model.table)
        _ = try await client.startRound(
            tableID: table.id,
            hostPlayerID: try #require(model.currentPlayerID)
        )
        await model.refreshTable()
        _ = try await client.lockPick(
            tableID: table.id,
            playerID: try #require(model.currentPlayerID),
            roundNumber: 1,
            pick: 2
        )

        await model.refreshTable()
        #expect(model.canReveal)
        #expect(model.table?.players.first?.avatarID == "fox")

        _ = try await client.revealRound(
            tableID: table.id,
            hostPlayerID: try #require(model.currentPlayerID),
            roundNumber: 1
        )
        await model.refreshTable()
        #expect(model.screen == .lobby)
        #expect(model.table?.currentRound == nil)
        #expect(model.result?.winnerName == "Liam")
        #expect(reportedResults == 1)
        await model.refreshTable()
        #expect(reportedResults == 1)

        _ = try await client.startRound(
            tableID: table.id,
            hostPlayerID: try #require(model.currentPlayerID)
        )
        await model.refreshTable()
        #expect(model.table?.currentRound?.number == 2)
        #expect(model.result == nil)
    }

    @Test
    @MainActor
    func screenTimeRestrictionBlocksMultiplayerActions() async {
        let model = GameModel(client: PreviewGameClient())
        await model.setMultiplayerRestricted(true)

        #expect(await model.createTable(name: "Friday", displayName: "Maya") == false)
        #expect(model.screen == .home)
        #expect(
            model.errorMessage
                == String(localized: "Multiplayer is unavailable because of Screen Time settings.")
        )
    }

    @Test
    @MainActor
    func screenTimeRestrictionLeavesAnActiveTable() async {
        let model = GameModel(client: PreviewGameClient())

        #expect(await model.createTable(name: "Friday", displayName: "Maya"))
        await model.setMultiplayerRestricted(true)

        #expect(model.screen == .home)
        #expect(model.table == nil)
    }

    @Test
    @MainActor
    func savedMembershipRestoresAfterRelaunch() async {
        let client = PreviewGameClient()
        let store = VolatileGameSessionStore()
        let original = GameModel(client: client, sessionStore: store)

        #expect(await original.createTable(name: "Friday Mini Match", displayName: "Maya"))
        let restored = GameModel(client: client, sessionStore: store)

        #expect(await restored.restoreSession())
        #expect(restored.screen == .lobby)
        #expect(restored.table?.id == original.table?.id)
        #expect(restored.currentPlayerID == original.currentPlayerID)
    }

    @Test
    @MainActor
    func savedMembershipDoesNotCrossGameCenterAccounts() async {
        let client = PreviewGameClient()
        let store = VolatileGameSessionStore()
        let original = GameModel(client: client, sessionStore: store)
        let identity = GameCenterIdentityDTO(
            teamPlayerId: "first-account",
            publicKeyUrl: "https://example.com/key",
            signature: Data(),
            salt: Data(),
            timestamp: "0"
        )

        #expect(await original.createTable(
            name: "Friday Mini Match",
            displayName: "Maya",
            gameCenterIdentity: identity
        ))

        let restored = GameModel(client: client, sessionStore: store)
        #expect(await restored.restoreSession(gameCenterPlayerID: "second-account") == false)
        #expect(restored.screen == .home)
        #expect(store.load() == nil)
    }

    @Test
    @MainActor
    func restorationStopsWhenGameCenterIdentityChangesDuringTheRequest() async {
        let client = PreviewGameClient()
        let store = VolatileGameSessionStore()
        let original = GameModel(client: client, sessionStore: store)
        let identity = GameCenterIdentityDTO(
            teamPlayerId: "first-account",
            publicKeyUrl: "https://example.com/key",
            signature: Data(),
            salt: Data(),
            timestamp: "0"
        )

        #expect(await original.createTable(
            name: "Friday Mini Match",
            displayName: "Maya",
            gameCenterIdentity: identity
        ))

        let restored = GameModel(client: client, sessionStore: store)
        #expect(await restored.restoreSession(
            gameCenterPlayerID: "first-account",
            identityIsCurrent: { false }
        ) == false)
        #expect(restored.screen == .home)
        #expect(store.load() == nil)
    }

    @Test
    @MainActor
    func staleRestorationPreservesAReplacementSession() async throws {
        let client = LifecycleTestGameClient(delaysGetTable: true)
        let store = VolatileGameSessionStore()
        let original = GameModel(client: client, sessionStore: store)

        #expect(await original.createTable(name: "Original", displayName: "Maya"))

        let restored = GameModel(client: client, sessionStore: store)
        let restoration = Task { await restored.restoreSession() }
        await client.waitUntilGetTableIsPending()

        #expect(await restored.createTable(name: "Replacement", displayName: "Maya"))
        let replacement = try #require(store.load())
        await client.resumeGetTable()

        #expect(await restoration.value == false)
        #expect(restored.table?.name == "Replacement")
        #expect(store.load() == replacement)
    }

    @Test
    @MainActor
    func staleRestorationFailureDoesNotReconnectAReplacementSession() async throws {
        let client = LifecycleTestGameClient(
            getTableError: .server("offline"),
            delaysGetTable: true
        )
        let store = VolatileGameSessionStore()
        let original = GameModel(client: client, sessionStore: store)

        #expect(await original.createTable(name: "Original", displayName: "Maya"))

        let restored = GameModel(client: client, sessionStore: store)
        let restoration = Task { await restored.restoreSession() }
        await client.waitUntilGetTableIsPending()

        #expect(await restored.createTable(name: "Replacement", displayName: "Maya"))
        let replacement = try #require(store.load())
        await client.resumeGetTable()

        #expect(await restoration.value == false)
        #expect(restored.table?.name == "Replacement")
        #expect(!restored.isReconnecting)
        #expect(store.load() == replacement)
    }

    @Test
    @MainActor
    func authenticationFailureKeepsTheSavedSessionReconnectable() async throws {
        let client = LifecycleTestGameClient(getTableError: .unauthenticated)
        let store = VolatileGameSessionStore()
        let model = GameModel(client: client, sessionStore: store)

        #expect(await model.createTable(name: "Friday Mini Match", displayName: "Maya"))
        let saved = try #require(store.load())

        await model.refreshTable()

        #expect(model.screen == .lobby)
        #expect(model.table != nil)
        #expect(model.isReconnecting)
        #expect(store.load() == saved)

        let restored = GameModel(client: client, sessionStore: store)
        #expect(await restored.restoreSession() == false)
        #expect(restored.isReconnecting)
        #expect(store.load() == saved)
    }

    @Test
    @MainActor
    func delayedMutationResponseCannotOverwriteAReplacementSession() async {
        let client = LifecycleTestGameClient()
        let model = GameModel(client: client, sessionStore: VolatileGameSessionStore())

        #expect(await model.createTable(name: "First", displayName: "Maya"))
        let delayedStart = Task { await model.startRound() }
        await client.waitUntilStartRoundIsPending()

        model.discardSession()
        #expect(await model.createTable(name: "Replacement", displayName: "Maya"))
        await client.resumeStartRound()
        await delayedStart.value

        #expect(model.table?.name == "Replacement")
        #expect(model.table?.currentRound == nil)
        #expect(!model.isShowingError)
    }

    @Test
    @MainActor
    func restrictionDiscardsTheLocalSessionWhenLeaveCannotReachTheServer() async {
        let store = VolatileGameSessionStore()
        let client = LifecycleTestGameClient(leaveError: .server("offline"))
        let model = GameModel(client: client, sessionStore: store)

        #expect(await model.createTable(name: "Friday", displayName: "Maya"))
        await model.setMultiplayerRestricted(true)

        #expect(model.screen == .home)
        #expect(model.table == nil)
        #expect(store.load() == nil)
    }

    @Test
    @MainActor
    func terminalPollClearsTheSavedSession() async throws {
        let client = PreviewGameClient()
        let store = VolatileGameSessionStore()
        let model = GameModel(client: client, sessionStore: store)

        #expect(await model.createTable(name: "Friday Mini Match", displayName: "Maya"))
        let tableID = try #require(model.table?.id)
        let playerID = try #require(model.currentPlayerID)
        try await client.leaveTable(tableID: tableID, playerID: playerID)

        await model.refreshTable()

        #expect(model.screen == .home)
        #expect(model.table == nil)
        #expect(model.isShowingError)
        #expect(store.load() == nil)
        #expect(await GameModel(client: client, sessionStore: store).restoreSession() == false)
    }

    @Test
    @MainActor
    func repeatedLeaveAfterCommittedMutationReturnsHome() async throws {
        let client = PreviewGameClient()
        let model = GameModel(client: client, sessionStore: VolatileGameSessionStore())

        #expect(await model.createTable(name: "Friday Mini Match", displayName: "Maya"))
        try await client.leaveTable(
            tableID: try #require(model.table?.id),
            playerID: try #require(model.currentPlayerID)
        )

        await model.leaveTable()

        #expect(model.screen == .home)
        #expect(model.table == nil)
        #expect(!model.isShowingError)
    }

    @Test
    @MainActor
    func leavingRemovesThePlayerBeforeReturningHome() async {
        let client = PreviewGameClient()
        let model = GameModel(client: client)

        #expect(await model.createTable(name: "Friday", displayName: "Maya"))
        let tableID = try! #require(model.table?.id)
        await model.leaveTable()

        #expect(model.screen == .home)
        #expect(model.table == nil)
        await #expect(throws: GameClientError.self) {
            _ = try await client.getTable(id: tableID)
        }
    }
}

private actor LifecycleTestGameClient: GameClient {
    private let base = PreviewGameClient()
    private let leaveError: GameClientError?
    private let getTableError: GameClientError?
    private let delaysGetTable: Bool
    private var startRoundContinuation: CheckedContinuation<Void, Never>?
    private var getTableContinuation: CheckedContinuation<Void, Never>?

    init(
        leaveError: GameClientError? = nil,
        getTableError: GameClientError? = nil,
        delaysGetTable: Bool = false
    ) {
        self.leaveError = leaveError
        self.getTableError = getTableError
        self.delaysGetTable = delaysGetTable
    }

    func waitUntilStartRoundIsPending() async {
        while startRoundContinuation == nil {
            await Task.yield()
        }
    }

    func resumeStartRound() {
        startRoundContinuation?.resume()
        startRoundContinuation = nil
    }

    func waitUntilGetTableIsPending() async {
        while getTableContinuation == nil {
            await Task.yield()
        }
    }

    func resumeGetTable() {
        getTableContinuation?.resume()
        getTableContinuation = nil
    }

    func createTable(
        name: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?,
        joinCode: String?
    ) async throws -> GameSession {
        try await base.createTable(
            name: name,
            displayName: displayName,
            avatarID: avatarID,
            gameCenterIdentity: gameCenterIdentity,
            joinCode: joinCode
        )
    }

    func joinTable(
        code: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity: GameCenterIdentityDTO?
    ) async throws -> GameSession {
        try await base.joinTable(
            code: code,
            displayName: displayName,
            avatarID: avatarID,
            gameCenterIdentity: gameCenterIdentity
        )
    }

    func leaveTable(tableID: String, playerID: String) async throws {
        if let leaveError {
            throw leaveError
        }
        try await base.leaveTable(tableID: tableID, playerID: playerID)
    }

    func lockPick(
        tableID: String,
        playerID: String,
        roundNumber: UInt32,
        pick: UInt64
    ) async throws -> GameTable {
        try await base.lockPick(
            tableID: tableID,
            playerID: playerID,
            roundNumber: roundNumber,
            pick: pick
        )
    }

    func startRound(tableID: String, hostPlayerID: String) async throws -> GameTable {
        await withCheckedContinuation { startRoundContinuation = $0 }
        return try await base.startRound(tableID: tableID, hostPlayerID: hostPlayerID)
    }

    func revealRound(
        tableID: String,
        hostPlayerID: String,
        roundNumber: UInt32
    ) async throws -> GameTable {
        try await base.revealRound(
            tableID: tableID,
            hostPlayerID: hostPlayerID,
            roundNumber: roundNumber
        )
    }

    func getTable(id: String) async throws -> GameTable {
        if let getTableError {
            if delaysGetTable {
                await withCheckedContinuation { getTableContinuation = $0 }
            }
            throw getTableError
        }
        let table = try await base.getTable(id: id)
        if delaysGetTable {
            await withCheckedContinuation { getTableContinuation = $0 }
        }
        return table
    }

    func deleteProfile() async throws {
        try await base.deleteProfile()
    }
}
