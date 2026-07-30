import Foundation
import Testing
@testable import MiniMatch

struct GameTableTests {
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
}
