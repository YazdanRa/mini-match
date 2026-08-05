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
        #expect(table.lastResult?.winnerAchievementIDs == [])
    }

    @Test
    func winnerAchievementsDecodeWithoutPrivateCounters() throws {
        let json = """
        {
          "roundNumber": 5,
          "selections": [],
          "winnerPlayerId": "maya",
          "localPlayerLeaderboardScore": "64",
          "winnerAchievementIds": [
            "com.yazdanra.minimatch.achievement.twoWinStreak",
            "com.yazdanra.minimatch.achievement.sixtyFourRoundWins"
          ]
        }
        """

        let result = try JSONDecoder().decode(ResultDTO.self, from: Data(json.utf8)).model()

        #expect(result.winnerAchievementIDs == [
            "com.yazdanra.minimatch.achievement.twoWinStreak",
            "com.yazdanra.minimatch.achievement.sixtyFourRoundWins",
        ])
        #expect(result.localPlayerLeaderboardScore == 64)
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

    @Test
    func finalPlayerLeaveResponseDecodesAtTheIgnoredTransportBoundary() async throws {
        let json = """
        {
          "table": {
            "id": "table-1",
            "name": "Friday Mini Match",
            "joinCode": "7X2G9K",
            "state": "TABLE_STATE_ACTIVE",
            "stateVersion": "2",
            "eventSequence": "2"
          }
        }
        """

        let baseURL = try #require(URL(string: "https://example.com"))
        let client = ConnectGameClient(
            baseURL: baseURL,
            authorizationToken: { "test-token" },
            send: { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(
                          url: url,
                          statusCode: 200,
                          httpVersion: nil,
                          headerFields: nil
                      )
                else {
                    throw GameClientError.invalidResponse
                }
                return (Data(json.utf8), response)
            }
        )

        try await client.leaveTable(tableID: "table-1", playerID: "maya")
    }
}
