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
            {"id": "maya", "displayName": "Maya", "wins": 5},
            {"id": "liam", "displayName": "Liam", "avatar": "frog"}
          ],
          "currentRound": {
            "number": 1,
            "phase": "ROUND_PHASE_ACCEPTING_PICKS"
          },
          "lastResult": {
            "roundNumber": 1,
            "selections": [{"playerId": "maya", "displayName": "Maya", "pick": {}, "wins": 5}]
          }
        }
        """

        let table = try JSONDecoder().decode(TableDTO.self, from: Data(json.utf8)).model()

        #expect(table.players == [
            GamePlayer(
                id: "maya",
                displayName: "Maya",
                avatarID: "spark",
                isLocked: false,
                wins: 5
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
        #expect(table.players[1].wins == 0)
        #expect(table.lastResult?.selections.first?.pick == 0)
        #expect(table.lastResult?.selections.first?.displayName == "Maya")
        #expect(table.lastResult?.selections.first?.wins == 5)
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

    @Test
    func dailyGlobalResponseDecodesPrivateActorFieldsAndUInt64Strings() throws {
        let json = """
        {
          "serverTimeUnixSeconds": "1786017600",
          "currentRound": {
            "roundDate": "2026-08-06",
            "closesAtUnixSeconds": "1786060800",
            "localPick": {"value": "18446744073709551615"}
          },
          "previousResult": {
            "roundDate": "2026-08-05",
            "status": "DAILY_GLOBAL_RESULT_STATUS_WINNER",
            "participantCount": "12345",
            "winningPick": {"value": "3"},
            "localPick": {"value": "3"}
          },
          "localPlayerDailyWins": "12"
        }
        """

        let table = try JSONDecoder()
            .decode(DailyGlobalTableResponseDTO.self, from: Data(json.utf8))
            .model()

        #expect(table.currentRound.localPick == UInt64.max)
        #expect(table.previousResult?.participantCount == 12_345)
        #expect(table.previousResult?.localPlayerWon == true)
        #expect(table.localPlayerDailyWins == 12)
    }

    @Test
    func dailyGlobalProtoDefaultsAndEveryResultStatusDecode() throws {
        let statuses: [(String, DailyGlobalResult.Status)] = [
            ("DAILY_GLOBAL_RESULT_STATUS_CALCULATING", .calculating),
            ("DAILY_GLOBAL_RESULT_STATUS_EMPTY", .empty),
            ("DAILY_GLOBAL_RESULT_STATUS_INSUFFICIENT_PLAYERS", .insufficientPlayers),
            ("DAILY_GLOBAL_RESULT_STATUS_NO_UNIQUE_PICK", .noUniquePick),
        ]

        for (wireStatus, expected) in statuses {
            let result = try DailyGlobalResultDTO(
                roundDate: "2026-08-05",
                status: wireStatus,
                participantCount: nil,
                winningPick: nil,
                localPick: nil
            ).model()
            #expect(result.status == expected)
            #expect(result.participantCount == 0)
            #expect(!result.localPlayerWon)
        }

        let response = try DailyGlobalTableResponseDTO(
            serverTimeUnixSeconds: "1786017600",
            currentRound: DailyGlobalRoundDTO(
                roundDate: "2026-08-06",
                closesAtUnixSeconds: "1786060800",
                localPick: nil
            ),
            previousResult: nil,
            localPlayerDailyWins: nil
        ).model()
        #expect(response.previousResult == nil)
        #expect(response.localPlayerDailyWins == 0)
    }

    @Test
    func dailyGlobalResponseRejectsMalformedOrPrematurePicks() {
        #expect(throws: GameClientError.self) {
            try DailyGlobalRoundDTO(
                roundDate: "2026-08-06",
                closesAtUnixSeconds: "1786060800",
                localPick: PickDTO(value: "0")
            ).model()
        }
        #expect(throws: GameClientError.self) {
            try DailyGlobalRoundDTO(
                roundDate: "2026-08-06",
                closesAtUnixSeconds: "1786060800",
                localPick: PickDTO(value: "18446744073709551616")
            ).model()
        }
        #expect(throws: GameClientError.self) {
            try DailyGlobalResultDTO(
                roundDate: "2026-08-05",
                status: "DAILY_GLOBAL_RESULT_STATUS_CALCULATING",
                participantCount: nil,
                winningPick: PickDTO(value: "1"),
                localPick: nil
            ).model()
        }
        #expect(throws: GameClientError.self) {
            try DailyGlobalResultDTO(
                roundDate: "2026-08-05",
                status: "DAILY_GLOBAL_RESULT_STATUS_UNSPECIFIED",
                participantCount: nil,
                winningPick: nil,
                localPick: nil
            ).model()
        }
    }

    @Test
    func dailyGlobalLockSendsIdentityAndAppCheck() async throws {
        let recorder = RequestRecorder()
        let json = """
        {
          "serverTimeUnixSeconds": "1786017600",
          "currentRound": {
            "roundDate": "2026-08-06",
            "closesAtUnixSeconds": "1786060800",
            "localPick": {"value": "7"}
          },
          "localPlayerDailyWins": "4"
        }
        """
        let client = ConnectGameClient(
            baseURL: try #require(URL(string: "https://example.com")),
            authorizationToken: { "firebase-token" },
            appCheckToken: { "app-check-token" },
            send: { request in
                await recorder.capture(request)
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
        let identity = GameCenterIdentityDTO(
            teamPlayerId: "team-player",
            publicKeyUrl: "https://example.com/key",
            signature: Data([1, 2]),
            salt: Data([3, 4]),
            timestamp: "18446744073709551615"
        )

        let table = try await client.lockDailyGlobalPick(
            roundDate: "2026-08-06",
            pick: UInt64.max,
            gameCenterIdentity: identity
        )
        let capturedRequest = await recorder.request
        let request = try #require(capturedRequest)
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let encodedIdentity = try #require(object["gameCenterIdentity"] as? [String: Any])
        let encodedPick = try #require(object["pick"] as? [String: Any])

        #expect(request.url?.path.hasSuffix("/GetDailyGlobalTable") == false)
        #expect(request.url?.path.hasSuffix("/LockDailyGlobalPick") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer firebase-token")
        #expect(request.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "app-check-token")
        #expect(object["roundDate"] as? String == "2026-08-06")
        #expect(encodedPick["value"] as? String == String(UInt64.max))
        #expect(encodedIdentity["teamPlayerId"] as? String == "team-player")
        #expect(encodedIdentity["timestamp"] as? String == String(UInt64.max))
        #expect(table.currentRound.localPick == 7)
        #expect(table.localPlayerDailyWins == 4)
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func capture(_ request: URLRequest) {
        self.request = request
    }
}
