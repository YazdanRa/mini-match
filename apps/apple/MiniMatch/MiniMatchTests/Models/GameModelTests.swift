import Foundation
import Testing
@testable import MiniMatch

struct GameModelTests {
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
        #expect(!model.canReveal)

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

        #expect(model.screen == .result)
        #expect(model.result?.winnerName == "Liam")
        #expect(model.result?.winningPick == 5)
        #expect(model.result?.rows.filter { $0.status == .duplicate }.count == 2)
        #expect(model.table?.players.first { $0.id == "liam" }?.wins == 1)
        #expect(model.table?.currentRound?.number == 2)

        for _ in 2...5 {
            model.nextRound()
            model.pickText = "2"
            await model.lockPick()
            await model.revealRound()
        }

        #expect(model.table?.state == .finished)
        #expect(model.table?.winnerPlayerID == "liam")
        #expect(model.table?.currentRound == nil)

        model.nextRound()
        #expect(model.screen == .home)
    }

    @Test
    @MainActor
    func joinedPlayerReceivesPreviewReveal() async {
        let model = GameModel(client: PreviewGameClient())

        #expect(await model.joinTable(code: "7X2G9K", displayName: "Maya"))
        #expect(!model.isHost)

        model.pickText = "2"
        await model.lockPick()

        #expect(model.screen == .result)
        #expect(model.result?.winnerName == "Liam")
        #expect(model.result?.winningPick == 5)
    }

    @Test
    @MainActor
    func tableRefreshConvergesRemoteStateOnce() async throws {
        let client = PreviewGameClient()
        let model = GameModel(client: client)

        #expect(await model.createTable(
            name: "Friday Mini Match",
            displayName: "Maya",
            avatarID: "fox"
        ))
        let table = try #require(model.table)
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
        #expect(model.screen == .result)

        model.nextRound()
        await model.refreshTable()
        #expect(model.screen == .lobby)
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
