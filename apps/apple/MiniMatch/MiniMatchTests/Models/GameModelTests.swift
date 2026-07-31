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
    func leavingRemovesThePlayerBeforeReturningHome() async {
        let client = PreviewGameClient()
        let model = GameModel(client: client)

        #expect(await model.createTable(name: "Friday", displayName: "Maya"))
        let tableID = try! #require(model.table?.id)
        await model.leaveTable()

        #expect(model.screen == .home)
        #expect(model.table == nil)
        let table = try? await client.getTable(id: tableID)
        #expect(table?.players.contains { $0.id == "local-player" } == false)
        #expect(table?.hostPlayerID == "zoe")
    }
}
