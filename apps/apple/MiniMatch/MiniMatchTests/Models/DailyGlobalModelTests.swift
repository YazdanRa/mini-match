import Foundation
import Testing
@testable import MiniMatch

struct DailyGlobalModelTests {
    @Test
    @MainActor
    func acceptsOnlyPositiveUInt64Picks() async {
        let model = makeModel(client: DailyGlobalTestClient())
        await model.refresh()

        for invalid in ["", "0", "-1", "1.5", "18446744073709551616"] {
            model.pickText = invalid
            #expect(!model.canSubmit)
        }
        model.pickText = "18446744073709551615"
        #expect(model.canSubmit)
    }

    @Test
    @MainActor
    func successfulPickIsImmutableAndReportsWinsWithTheVerifiedIdentity() async {
        let client = DailyGlobalTestClient()
        let identity = dailyIdentity(teamPlayerID: "verified-player")
        var report: (UInt64, String)?
        let model = DailyGlobalModel(
            client: client,
            identityProvider: { identity },
            winsReporter: { wins, identity in
                report = (wins, identity.teamPlayerId)
            },
            now: { Date(timeIntervalSince1970: 1_786_017_600) }
        )
        await model.refresh()
        model.pickText = "7"

        await model.submitPick()

        #expect(model.table?.currentRound.localPick == 7)
        #expect(model.pendingPick == nil)
        #expect(!model.canSubmit)
        #expect(report?.0 == 4)
        #expect(report?.1 == "verified-player")
    }

    @Test
    @MainActor
    func ambiguousFailureReconcilesTheCommittedPick() async {
        let client = DailyGlobalTestClient(lockBehavior: .commitThenFail)
        let model = makeModel(client: client)
        await model.refresh()
        model.pickText = "9"

        await model.submitPick()

        #expect(model.table?.currentRound.localPick == 9)
        #expect(model.pendingPick == nil)
        #expect(model.errorMessage.isEmpty)
    }

    @Test
    @MainActor
    func unresolvedSubmissionCanOnlyRetryTheOriginalPick() async {
        let client = DailyGlobalTestClient(lockBehavior: .failWithoutCommit)
        let model = makeModel(client: client)
        await model.refresh()
        model.pickText = "11"

        await model.submitPick()
        model.pickText = "12"

        #expect(model.pendingPick == 11)
        #expect(model.pickText == "11")
        #expect(model.canSubmit)
    }

    @Test
    @MainActor
    func staleRoundRefreshClearsThePendingPick() async {
        let client = DailyGlobalTestClient(lockBehavior: .advanceThenFail)
        let model = makeModel(client: client)
        await model.refresh()
        model.pickText = "9"

        await model.submitPick()

        #expect(model.table?.currentRound.roundDate == "2026-08-07")
        #expect(model.table?.currentRound.localPick == nil)
        #expect(model.pendingPick == nil)
        #expect(model.pickText.isEmpty)
    }

    @Test
    @MainActor
    func refreshFailureRetainsDataAndCountdownUsesServerTime() async {
        let client = DailyGlobalTestClient()
        let model = makeModel(client: client)
        await model.refresh()
        await client.failFutureRefreshes()

        await model.refresh()

        #expect(model.table?.currentRound.roundDate == "2026-08-06")
        #expect(!model.errorMessage.isEmpty)
        #expect(
            model.timeRemaining(at: Date(timeIntervalSince1970: 1_786_017_700))
                == 43_100
        )
        #expect(
            model.timeRemaining(at: Date(timeIntervalSince1970: 1_786_100_000))
                == 0
        )
    }

    @Test
    @MainActor
    func calculatingResultRefreshesUntilItSettles() async {
        let client = DailyGlobalTestClient(calculatingResponses: 2)
        let model = DailyGlobalModel(
            client: client,
            identityProvider: { dailyIdentity(teamPlayerID: "team-player") },
            now: { Date(timeIntervalSince1970: 1_786_017_600) },
            sleeper: { _ in }
        )
        await model.refresh()
        #expect(model.table?.previousResult?.status == .calculating)
        await client.failNextRefresh()

        await model.refreshUntilPreviousResultSettles()

        #expect(model.table?.previousResult?.status == .winner)
        #expect(await client.requestCount() == 3)
    }

    @Test
    @MainActor
    func authenticationLossClearsActorPrivateDailyData() async {
        let identityState = DailyIdentityState(identity: dailyIdentity(teamPlayerID: "team-player"))
        let model = DailyGlobalModel(
            client: DailyGlobalTestClient(),
            identityProvider: { identityState.identity },
            now: { Date(timeIntervalSince1970: 1_786_017_600) }
        )
        await model.refresh()
        model.pickText = "7"
        await model.submitPick()
        #expect(model.table?.currentRound.localPick == 7)

        identityState.identity = nil
        await model.refresh()

        #expect(model.table == nil)
        #expect(model.pendingPick == nil)
        #expect(model.pickText.isEmpty)
        #expect(model.requiresAuthentication)
    }

    @Test
    @MainActor
    func staleIdentityFailureCannotClearANewAccountSnapshot() async {
        let identities = DelayedIdentitySequence()
        let model = DailyGlobalModel(
            client: DailyGlobalTestClient(),
            identityProvider: { await identities.next() },
            now: { Date(timeIntervalSince1970: 1_786_017_600) }
        )
        await model.refresh()
        model.pickText = "7"
        let staleSubmission = Task { await model.submitPick() }
        while !identities.isWaiting {
            await Task.yield()
        }

        model.resetForAuthenticationChange()
        await model.refresh()
        #expect(model.table != nil)
        identities.resumeWithMissingIdentity()
        await staleSubmission.value

        #expect(model.table != nil)
        #expect(!model.requiresAuthentication)
    }

    @MainActor
    private func makeModel(client: DailyGlobalTestClient) -> DailyGlobalModel {
        DailyGlobalModel(
            client: client,
            identityProvider: { dailyIdentity(teamPlayerID: "team-player") },
            now: { Date(timeIntervalSince1970: 1_786_017_600) }
        )
    }
}

@MainActor
private final class DailyIdentityState {
    var identity: GameCenterIdentityDTO?

    init(identity: GameCenterIdentityDTO?) {
        self.identity = identity
    }
}

@MainActor
private final class DelayedIdentitySequence {
    private var callCount = 0
    private var continuation: CheckedContinuation<GameCenterIdentityDTO?, Never>?
    private(set) var isWaiting = false

    func next() async -> GameCenterIdentityDTO? {
        callCount += 1
        if callCount == 2 {
            isWaiting = true
            return await withCheckedContinuation { continuation = $0 }
        }
        return dailyIdentity(teamPlayerID: callCount == 1 ? "old-player" : "new-player")
    }

    func resumeWithMissingIdentity() {
        continuation?.resume(returning: nil)
        continuation = nil
        isWaiting = false
    }
}

private actor DailyGlobalTestClient: DailyGlobalClient {
    enum LockBehavior: Sendable {
        case succeed
        case commitThenFail
        case advanceThenFail
        case failWithoutCommit
    }

    private var table = DailyGlobalTable(
        serverTime: Date(timeIntervalSince1970: 1_786_017_600),
        currentRound: DailyGlobalRound(
            roundDate: "2026-08-06",
            closesAt: Date(timeIntervalSince1970: 1_786_060_800),
            localPick: nil
        ),
        previousResult: nil,
        localPlayerDailyWins: 4
    )
    private let lockBehavior: LockBehavior
    private let calculatingResponses: Int
    private var refreshesFail = false
    private var nextRefreshFails = false
    private var dailyRequestCount = 0

    init(lockBehavior: LockBehavior = .succeed, calculatingResponses: Int = 0) {
        self.lockBehavior = lockBehavior
        self.calculatingResponses = calculatingResponses
    }

    func failFutureRefreshes() {
        refreshesFail = true
    }

    func failNextRefresh() {
        nextRefreshFails = true
    }

    func getDailyGlobalTable(
        gameCenterIdentity _: GameCenterIdentityDTO
    ) async throws -> DailyGlobalTable {
        dailyRequestCount += 1
        if refreshesFail { throw GameClientError.server("offline") }
        if nextRefreshFails {
            nextRefreshFails = false
            throw GameClientError.server("offline")
        }
        if calculatingResponses > 0 {
            return withPreviousResult(
                status: dailyRequestCount <= calculatingResponses ? .calculating : .winner
            )
        }
        return table
    }

    func requestCount() -> Int {
        dailyRequestCount
    }

    func lockDailyGlobalPick(
        roundDate: String,
        pick: UInt64,
        gameCenterIdentity _: GameCenterIdentityDTO
    ) async throws -> DailyGlobalTable {
        guard roundDate == table.currentRound.roundDate else {
            throw GameClientError.failedPrecondition
        }
        switch lockBehavior {
        case .succeed:
            table = withCurrentRound(date: roundDate, pick: pick)
            return table
        case .commitThenFail:
            table = withCurrentRound(date: roundDate, pick: pick)
            throw GameClientError.server("connection lost")
        case .advanceThenFail:
            table = withCurrentRound(date: "2026-08-07", pick: nil)
            throw GameClientError.failedPrecondition
        case .failWithoutCommit:
            refreshesFail = true
            throw GameClientError.server("connection lost")
        }
    }

    private func withCurrentRound(date: String, pick: UInt64?) -> DailyGlobalTable {
        DailyGlobalTable(
            serverTime: table.serverTime,
            currentRound: DailyGlobalRound(
                roundDate: date,
                closesAt: date == "2026-08-06"
                    ? Date(timeIntervalSince1970: 1_786_060_800)
                    : Date(timeIntervalSince1970: 1_786_147_200),
                localPick: pick
            ),
            previousResult: table.previousResult,
            localPlayerDailyWins: table.localPlayerDailyWins
        )
    }

    private func withPreviousResult(status: DailyGlobalResult.Status) -> DailyGlobalTable {
        DailyGlobalTable(
            serverTime: table.serverTime,
            currentRound: table.currentRound,
            previousResult: DailyGlobalResult(
                roundDate: "2026-08-05",
                status: status,
                participantCount: 2,
                winningPick: status == .winner ? 3 : nil,
                localPick: 3
            ),
            localPlayerDailyWins: table.localPlayerDailyWins
        )
    }
}

private func dailyIdentity(teamPlayerID: String) -> GameCenterIdentityDTO {
    GameCenterIdentityDTO(
        teamPlayerId: teamPlayerID,
        publicKeyUrl: "https://example.com/key",
        signature: Data([1]),
        salt: Data([2]),
        timestamp: "1786017600000"
    )
}
