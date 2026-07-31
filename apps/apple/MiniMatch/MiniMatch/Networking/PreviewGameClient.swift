import Foundation

actor PreviewGameClient: GameClient {
    private var table: GameTable?
    private var currentPlayerID: String
    private var localPick: UInt64?

    init(
        table: GameTable? = nil,
        localPick: UInt64? = nil
    ) {
        self.table = table
        currentPlayerID = PreviewFixtures.currentPlayerID
        self.localPick = localPick
    }

    func createTable(
        name: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity _: GameCenterIdentityDTO?,
        joinCode: String?
    ) async throws -> GameSession {
        currentPlayerID = "local-player"
        let created = PreviewFixtures.table(
            name: name,
            hostID: currentPlayerID,
            hostName: displayName,
            hostAvatarID: avatarID
        )
        let table = joinCode.map { withJoinCode($0, in: created) } ?? created
        self.table = table
        return GameSession(table: table, playerID: currentPlayerID)
    }

    func joinTable(
        code: String,
        displayName: String,
        avatarID: String,
        gameCenterIdentity _: GameCenterIdentityDTO?
    ) async throws -> GameSession {
        currentPlayerID = "local-player"
        var joined = PreviewFixtures.table(
            name: "Friday Mini Match",
            hostID: "casey",
            hostName: "Casey",
            hostAvatarID: "fox"
        )
        joined = withPlayer(
            GamePlayer(
                id: currentPlayerID,
                displayName: displayName,
                avatarID: avatarID,
                isLocked: false
            ),
            addedTo: joined
        )
        joined = withJoinCode(code, in: joined)
        table = joined
        return GameSession(table: joined, playerID: currentPlayerID)
    }

    func leaveTable(tableID: String, playerID: String) async throws {
        guard var table, table.id == tableID else {
            throw GameClientError.server(String(localized: "Table not found."))
        }
        table.players.removeAll { $0.id == playerID }
        if table.hostPlayerID == playerID, let nextHost = table.players.first {
            table = withHost(nextHost.id, in: table)
        }
        table.stateVersion += 1
        table.eventSequence += 1
        self.table = table
    }

    func lockPick(
        tableID: String,
        playerID: String,
        roundNumber: UInt32,
        pick: UInt64
    ) async throws -> GameTable {
        guard var table, table.id == tableID, table.currentRound?.number == roundNumber else {
            throw GameClientError.server(String(localized: "That round is no longer active."))
        }
        guard table.players.contains(where: { $0.id == playerID && !$0.isLocked }) else {
            throw GameClientError.server(String(localized: "This player has already locked a number."))
        }

        localPick = pick
        // ponytail: preview-only auto-lock keeps the local flow playable until Firestore supplies remote updates.
        for index in table.players.indices {
            table.players[index].isLocked = true
        }
        table.currentRound = GameRound(number: roundNumber, phase: .readyToReveal)
        table.stateVersion += 1
        table.eventSequence += 1
        self.table = table
        if playerID != table.hostPlayerID {
            return try await revealRound(
                tableID: tableID,
                hostPlayerID: table.hostPlayerID,
                roundNumber: roundNumber
            )
        }
        return table
    }

    func startRound(tableID: String, hostPlayerID: String) async throws -> GameTable {
        guard var table,
              table.id == tableID,
              table.hostPlayerID == hostPlayerID,
              table.currentRound == nil,
              table.players.count >= 2
        else {
            throw GameClientError.server(String(localized: "The table is not ready."))
        }
        let roundNumber = (table.lastResult?.roundNumber ?? 0) + 1
        table.currentRound = GameRound(number: roundNumber, phase: .acceptingPicks)
        table.stateVersion += 1
        table.eventSequence += 1
        localPick = nil
        self.table = table
        return table
    }

    func revealRound(
        tableID: String,
        hostPlayerID: String,
        roundNumber: UInt32
    ) async throws -> GameTable {
        guard var table,
              table.id == tableID,
              table.hostPlayerID == hostPlayerID,
              table.currentRound?.number == roundNumber,
              table.allPlayersLocked,
              let localPick
        else {
            throw GameClientError.server(String(localized: "The round is not ready to reveal."))
        }

        let winnerID = "liam"
        let winnerPick = localPick <= UInt64.max - 3 ? localPick + 3 : 0
        let selections = table.players.map { player in
            GameSelection(
                playerID: player.id,
                displayName: player.displayName,
                pick: player.id == winnerID ? winnerPick : localPick
            )
        }
        table.lastResult = GameRoundResult(
            roundNumber: roundNumber,
            selections: selections,
            winnerPlayerID: winnerID
        )
        for index in table.players.indices {
            table.players[index].isLocked = false
        }
        table.currentRound = nil
        table.stateVersion += 1
        table.eventSequence += 1
        self.table = table
        return table
    }

    func getTable(id: String) async throws -> GameTable {
        guard let table, table.id == id else {
            throw GameClientError.server(String(localized: "Table not found."))
        }
        return table
    }

    func deleteProfile() async throws {}

    private func withPlayer(_ player: GamePlayer, addedTo table: GameTable) -> GameTable {
        var updated = table
        updated.players.append(player)
        return updated
    }

    private func withJoinCode(_ code: String, in table: GameTable) -> GameTable {
        GameTable(
            id: table.id,
            name: table.name,
            joinCode: code.uppercased(),
            hostPlayerID: table.hostPlayerID,
            players: table.players,
            currentRound: table.currentRound,
            lastResult: table.lastResult,
            stateVersion: table.stateVersion,
            eventSequence: table.eventSequence
        )
    }

    private func withHost(_ hostID: String, in table: GameTable) -> GameTable {
        GameTable(
            id: table.id,
            name: table.name,
            joinCode: table.joinCode,
            hostPlayerID: hostID,
            players: table.players,
            currentRound: table.currentRound,
            lastResult: table.lastResult,
            stateVersion: table.stateVersion,
            eventSequence: table.eventSequence
        )
    }
}

enum PreviewFixtures {
    static let currentPlayerID = "local-player"

    static var lobbyTable: GameTable {
        table(
            name: "Friday Mini Match",
            hostID: currentPlayerID,
            hostName: "Maya",
            hostAvatarID: "spark"
        )
    }

    static var readyTable: GameTable {
        var table = lobbyTable
        for index in table.players.indices {
            table.players[index].isLocked = true
        }
        table.currentRound = GameRound(number: 1, phase: .readyToReveal)
        return table
    }

    static var resultTable: GameTable {
        var table = lobbyTable
        table.lastResult = roundResult
        return table
    }

    static var result: ResultPresentation {
        ResultPresentation(table: resultTable, result: roundResult)
    }

    static let winnerRow = ResultPresentation.Row(
        playerID: "liam",
        displayName: "Liam",
        pick: 5,
        status: .winner
    )

    private static let roundResult = GameRoundResult(
        roundNumber: 1,
        selections: [
            GameSelection(playerID: currentPlayerID, displayName: "Maya", pick: 2),
            GameSelection(playerID: "zoe", displayName: "Zoe", pick: 2),
            GameSelection(playerID: "liam", displayName: "Liam", pick: 5),
        ],
        winnerPlayerID: "liam"
    )

    static func table(
        name: String,
        hostID: String,
        hostName: String,
        hostAvatarID: String
    ) -> GameTable {
        GameTable(
            id: "preview-table",
            name: name,
            joinCode: "7X2G9K",
            hostPlayerID: hostID,
            players: [
                GamePlayer(
                    id: hostID,
                    displayName: hostName,
                    avatarID: hostAvatarID,
                    isLocked: false
                ),
                GamePlayer(id: "zoe", displayName: "Zoe", avatarID: "owl", isLocked: false),
                GamePlayer(id: "liam", displayName: "Liam", avatarID: "frog", isLocked: false),
            ],
            currentRound: nil,
            lastResult: nil,
            stateVersion: 1,
            eventSequence: 1
        )
    }
}
