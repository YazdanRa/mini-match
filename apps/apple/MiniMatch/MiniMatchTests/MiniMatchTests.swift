import Foundation
import Testing
@testable import MiniMatch

struct MiniMatchTests {
    @Test
    func appleSignInNonceIsSecurelyShaped() throws {
        let nonce = try AppleSignInModel.randomNonce()

        #expect(nonce.count == 32)
        #expect(nonce.allSatisfy {
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._".contains($0)
        })
        #expect(
            AppleSignInModel.sha256("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
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
    func protoJSONDefaultsDecode() throws {
        let json = """
        {
          "id": "table-1",
          "name": "Friday Mini Match",
          "joinCode": "7X2G9K",
          "hostPlayerId": "maya",
          "players": [
            {"id": "maya", "displayName": "Maya"},
            {"id": "liam", "displayName": "Liam", "avatar": "frog"}
          ],
          "state": "TABLE_STATE_ACTIVE",
          "currentRound": {
            "number": 1,
            "phase": "ROUND_PHASE_ACCEPTING_PICKS"
          },
          "lastResult": {
            "roundNumber": 1,
            "selections": [{"playerId": "maya", "pick": {}}]
          },
          "winsToFinish": 5,
          "winnerLifetimeWins": "12"
        }
        """

        let table = try JSONDecoder().decode(TableDTO.self, from: Data(json.utf8)).model()

        #expect(table.players == [
            GamePlayer(
                id: "maya",
                displayName: "Maya",
                avatarID: "spark",
                wins: 0,
                isLocked: false
            ),
            GamePlayer(
                id: "liam",
                displayName: "Liam",
                avatarID: "frog",
                wins: 0,
                isLocked: false
            ),
        ])
        #expect(table.stateVersion == 0)
        #expect(table.eventSequence == 0)
        #expect(table.lastResult?.selections.first?.pick == 0)
        #expect(table.winnerLifetimeWins == 12)
    }

    @Test
    func completedMatchWinIsReportedOnlyForItsWinner() {
        let table = GameTable(
            id: "table-1",
            name: "Friday Mini Match",
            joinCode: "7X2G9K",
            hostPlayerID: "maya",
            players: [],
            state: .finished,
            currentRound: nil,
            lastResult: nil,
            winsToFinish: 5,
            stateVersion: 10,
            eventSequence: 10,
            winnerPlayerID: "maya",
            winnerLifetimeWins: 7
        )

        #expect(table.completedMatchWin(for: "maya") == CompletedMatchWin(
            matchID: "table-1",
            lifetimeWins: 7
        ))
        #expect(table.completedMatchWin(for: "liam") == nil)
        #expect(table.completedMatchWin(for: nil) == nil)
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
        #expect(model.errorMessage.contains("Screen Time"))
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
