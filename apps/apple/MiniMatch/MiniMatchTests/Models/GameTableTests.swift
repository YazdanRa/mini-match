import Foundation
import Testing
@testable import MiniMatch

struct GameTableTests {
    @Test
    func soloPlayerCannotMakeRoundReady() {
        let table = GameTable(
            id: "table-1",
            name: "Mini Match",
            joinCode: "7X2G9K",
            hostPlayerID: "maya",
            players: [
                GamePlayer(
                    id: "maya",
                    displayName: "Maya",
                    avatarID: "fox",
                    isLocked: true
                ),
            ],
            currentRound: nil,
            lastResult: nil,
            stateVersion: 1,
            eventSequence: 1
        )

        #expect(!table.allPlayersLocked)
    }

    @Test
    func resultUsesSnapshottedNameAfterPlayerLeaves() {
        let result = GameRoundResult(
            roundNumber: 1,
            selections: [
                GameSelection(playerID: "liam", displayName: "Liam", pick: 5),
            ],
            winnerPlayerID: "liam"
        )
        let table = GameTable(
            id: "table-1",
            name: "Mini Match",
            joinCode: "7X2G9K",
            hostPlayerID: "maya",
            players: [],
            currentRound: nil,
            lastResult: result,
            stateVersion: 1,
            eventSequence: 1
        )

        #expect(ResultPresentation(table: table, result: result).winnerName == "Liam")
    }

    @Test
    func anonymizedWinnerRemainsAWinner() {
        let result = GameRoundResult(
            roundNumber: 1,
            selections: [
                GameSelection(playerID: "deleted:table", displayName: "", pick: 5),
            ],
            winnerPlayerID: "deleted:table"
        )
        let table = GameTable(
            id: "table-1",
            name: "Mini Match",
            joinCode: "7X2G9K",
            hostPlayerID: "maya",
            players: [],
            currentRound: nil,
            lastResult: result,
            stateVersion: 1,
            eventSequence: 1
        )

        let presentation = ResultPresentation(table: table, result: result)
        #expect(presentation.winnerName == String(localized: "Player"))
        #expect(presentation.winningPick == 5)
    }
}
