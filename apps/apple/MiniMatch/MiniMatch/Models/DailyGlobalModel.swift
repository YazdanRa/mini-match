import Foundation
import Observation

struct DailyGlobalTable: Equatable, Sendable {
    let serverTime: Date
    let currentRound: DailyGlobalRound
    let previousResult: DailyGlobalResult?
    let localPlayerDailyWins: UInt64
}

struct DailyGlobalRound: Equatable, Sendable {
    let roundDate: String
    let closesAt: Date
    let localPick: UInt64?
}

struct DailyGlobalResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case calculating
        case empty
        case insufficientPlayers
        case noUniquePick
        case winner
    }

    let roundDate: String
    let status: Status
    let participantCount: UInt64
    let winningPick: UInt64?
    let localPick: UInt64?

    var localPlayerWon: Bool {
        status == .winner && localPick != nil && localPick == winningPick
    }
}

@MainActor
@Observable
final class DailyGlobalModel {
    typealias IdentityProvider = @MainActor @Sendable () async throws -> GameCenterIdentityDTO?
    typealias WinsReporter = @MainActor @Sendable (UInt64, GameCenterIdentityDTO) -> Void

    @ObservationIgnored private let client: any DailyGlobalClient
    @ObservationIgnored private let identityProvider: IdentityProvider
    @ObservationIgnored private let winsReporter: WinsReporter
    @ObservationIgnored private let now: @MainActor @Sendable () -> Date
    @ObservationIgnored private var serverTimeOffset: TimeInterval = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingRoundDate: String?

    private(set) var table: DailyGlobalTable?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isSubmitting = false
    private(set) var requiresAuthentication = false
    private(set) var errorMessage = ""
    private(set) var pendingPick: UInt64?
    var pickText = "" {
        didSet {
            if let pendingPick, pickText != String(pendingPick) {
                pickText = String(pendingPick)
            }
        }
    }

    init(
        client: any DailyGlobalClient,
        identityProvider: @escaping IdentityProvider,
        winsReporter: @escaping WinsReporter = { _, _ in },
        now: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.identityProvider = identityProvider
        self.winsReporter = winsReporter
        self.now = now
    }

    var canSubmit: Bool {
        table?.currentRound.localPick == nil
            && !isLoading
            && !isRefreshing
            && !isSubmitting
            && (pendingPick != nil || validPick != nil)
    }

    func timeRemaining(at date: Date) -> TimeInterval {
        guard let table else { return 0 }
        let estimatedServerTime = date.addingTimeInterval(serverTimeOffset)
        return max(0, table.currentRound.closesAt.timeIntervalSince(estimatedServerTime))
    }

    func refresh() async {
        guard !isLoading, !isRefreshing, !isSubmitting else { return }
        let requestGeneration = generation
        let isInitialLoad = table == nil
        isLoading = isInitialLoad
        isRefreshing = !isInitialLoad
        defer {
            if generation == requestGeneration {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            guard let identity = try await identityProvider() else {
                guard generation == requestGeneration else { return }
                clearAccountDataForAuthentication()
                return
            }
            requiresAuthentication = false
            let updated = try await client.getDailyGlobalTable(gameCenterIdentity: identity)
            guard generation == requestGeneration else { return }
            apply(updated)
            isLoading = false
            isRefreshing = false
            winsReporter(updated.localPlayerDailyWins, identity)
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            if let clientError = error as? GameClientError,
               case .unauthenticated = clientError {
                clearAccountDataForAuthentication()
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func submitPick() async {
        guard !isLoading, !isRefreshing, !isSubmitting,
              table?.currentRound.localPick == nil,
              let pick = pendingPick ?? validPick,
              let roundDate = table?.currentRound.roundDate
        else {
            if pendingPick == nil {
                errorMessage = String(localized: "Enter a positive whole number.")
            }
            return
        }

        let requestGeneration = generation
        var didStartRequest = false
        do {
            guard let identity = try await identityProvider() else {
                guard generation == requestGeneration else { return }
                clearAccountDataForAuthentication()
                return
            }
            guard generation == requestGeneration else { return }
            requiresAuthentication = false

            pendingPick = pick
            pendingRoundDate = roundDate
            pickText = String(pick)
            isSubmitting = true
            didStartRequest = true
            let updated = try await client.lockDailyGlobalPick(
                roundDate: roundDate,
                pick: pick,
                gameCenterIdentity: identity
            )
            guard generation == requestGeneration else { return }
            isSubmitting = false
            apply(updated)
            winsReporter(updated.localPlayerDailyWins, identity)
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            isSubmitting = false
        } catch {
            guard generation == requestGeneration else { return }
            isSubmitting = false
            let submissionError = error.localizedDescription
            guard didStartRequest else {
                errorMessage = submissionError
                return
            }
            await refresh()
            guard generation == requestGeneration, pendingPick != nil else { return }
            errorMessage = submissionError
        }
    }

    func resetForAuthenticationChange() {
        generation += 1
        table = nil
        isLoading = false
        isRefreshing = false
        isSubmitting = false
        requiresAuthentication = false
        errorMessage = ""
        pendingPick = nil
        pendingRoundDate = nil
        pickText = ""
        serverTimeOffset = 0
    }

    private var validPick: UInt64? {
        guard let pick = UInt64(pickText), pick > 0 else { return nil }
        return pick
    }

    private func apply(_ updated: DailyGlobalTable) {
        serverTimeOffset = updated.serverTime.timeIntervalSince(now())
        table = updated
        requiresAuthentication = false
        errorMessage = ""

        guard let pendingPick else { return }
        if updated.currentRound.roundDate != pendingRoundDate
            || updated.currentRound.localPick != nil {
            self.pendingPick = nil
            pendingRoundDate = nil
            pickText = updated.currentRound.localPick.map(String.init) ?? ""
        } else {
            pickText = String(pendingPick)
        }
    }

    private func clearAccountDataForAuthentication() {
        table = nil
        requiresAuthentication = true
        errorMessage = String(localized: "Sign in and try again.")
        pendingPick = nil
        pendingRoundDate = nil
        pickText = ""
        serverTimeOffset = 0
    }
}
