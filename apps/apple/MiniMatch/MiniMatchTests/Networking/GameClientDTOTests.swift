import Foundation
import Testing
@testable import MiniMatch

struct GameClientDTOTests {
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
    func connectErrorsUseLocalizedMessages() {
        #expect(
            ErrorResponse(code: "not_found").localizedMessage
                == String(localized: "Table not found.")
        )
        #expect(
            ErrorResponse(code: "unknown").localizedMessage
                == String(localized: "The request failed.")
        )
    }
}
