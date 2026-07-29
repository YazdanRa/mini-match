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
          "players": [{"id": "maya", "displayName": "Maya"}],
          "state": "TABLE_STATE_ACTIVE",
          "currentRound": {
            "number": 1,
            "phase": "ROUND_PHASE_ACCEPTING_PICKS"
          },
          "lastResult": {
            "roundNumber": 1,
            "selections": [{"playerId": "maya", "pick": {}}]
          },
          "winsToFinish": 5
        }
        """

        let table = try JSONDecoder().decode(TableDTO.self, from: Data(json.utf8)).model()

        #expect(table.players == [
            GamePlayer(id: "maya", displayName: "Maya", wins: 0, isLocked: false),
        ])
        #expect(table.stateVersion == 0)
        #expect(table.eventSequence == 0)
        #expect(table.lastResult?.selections.first?.pick == 0)
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
}
