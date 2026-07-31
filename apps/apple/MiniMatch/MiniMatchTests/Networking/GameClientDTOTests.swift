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
          "currentRound": {
            "number": 1,
            "phase": "ROUND_PHASE_ACCEPTING_PICKS"
          },
          "lastResult": {
            "roundNumber": 1,
            "selections": [{"playerId": "maya", "displayName": "Maya", "pick": {}}]
          }
        }
        """

        let table = try JSONDecoder().decode(TableDTO.self, from: Data(json.utf8)).model()

        #expect(table.players == [
            GamePlayer(
                id: "maya",
                displayName: "Maya",
                avatarID: "spark",
                isLocked: false
            ),
            GamePlayer(
                id: "liam",
                displayName: "Liam",
                avatarID: "frog",
                isLocked: false
            ),
        ])
        #expect(table.stateVersion == 0)
        #expect(table.eventSequence == 0)
        #expect(table.lastResult?.selections.first?.pick == 0)
        #expect(table.lastResult?.selections.first?.displayName == "Maya")
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
