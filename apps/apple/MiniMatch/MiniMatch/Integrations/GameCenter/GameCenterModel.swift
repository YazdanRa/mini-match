@preconcurrency import GameKit
import Observation
import UIKit

struct GameCenterAuthentication: Identifiable {
    let id = UUID()
    let viewController: UIViewController
}

struct GameCenterMatchmaking: Identifiable {
    let id = UUID()
    let viewController: GKMatchmakerViewController
    let createsTable: Bool
    let hostPlayerID: String
}

struct ActivityStartGate {
    private(set) var isActive = false

    mutating func begin() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }

    mutating func end() {
        isActive = false
    }
}

struct PendingLeaderboardScore {
    private(set) var value: Int?

    init(_ value: Int? = nil) {
        self.value = value
    }

    mutating func enqueue(_ score: UInt64, maximum: UInt64) {
        let score = Int(min(score, maximum))
        value = max(value ?? score, score)
    }

    mutating func complete(_ score: Int) {
        guard value == score else { return }
        value = nil
    }
}

struct PlayerScopedGeneration {
    private(set) var playerID: String?
    private(set) var value = 0

    @discardableResult
    mutating func bind(to playerID: String?) -> Bool {
        guard self.playerID != playerID else { return false }
        self.playerID = playerID
        value &+= 1
        return true
    }

    func matches(_ generation: Int, playerID: String) -> Bool {
        value == generation && self.playerID == playerID
    }
}

struct DailyLeaderboardEntry: Identifiable, Equatable {
    let playerID: String
    let rank: Int
    let displayName: String
    let score: Int
    let isLocalPlayer: Bool

    var id: String { playerID }

    init(
        playerID: String,
        rank: Int,
        displayName: String,
        score: Int,
        isLocalPlayer: Bool
    ) {
        self.playerID = playerID
        self.rank = rank
        self.displayName = displayName
        self.score = score
        self.isLocalPlayer = isLocalPlayer
    }

    init(_ entry: GKLeaderboard.Entry, localPlayerID: String) {
        playerID = entry.player.gamePlayerID
        rank = entry.rank
        displayName = entry.player.displayName
        score = entry.score
        isLocalPlayer = playerID == localPlayerID
    }
}

@MainActor
protocol AchievementPendingPersisting: AnyObject {
    func load(for playerID: String) -> Set<String>
    func save(_ achievementIDs: Set<String>, for playerID: String)
}

@MainActor
final class UserDefaultsAchievementPendingStore: AchievementPendingPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pendingGameCenterAchievements") {
        self.defaults = defaults
        self.key = key
    }

    func load(for playerID: String) -> Set<String> {
        Set(loadAll()[playerID] ?? [])
    }

    func save(_ achievementIDs: Set<String>, for playerID: String) {
        var all = loadAll()
        if achievementIDs.isEmpty {
            all.removeValue(forKey: playerID)
        } else {
            all[playerID] = achievementIDs.sorted()
        }
        if all.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(try? JSONEncoder().encode(all), forKey: key)
        }
    }

    private func loadAll() -> [String: [String]] {
        defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([String: [String]].self, from: $0)
        } ?? [:]
    }
}

@MainActor
protocol LeaderboardScorePendingPersisting: AnyObject {
    func load(for playerID: String) -> Int?
    func save(_ score: Int?, for playerID: String)
}

@MainActor
final class UserDefaultsLeaderboardScorePendingStore: LeaderboardScorePendingPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pendingGameCenterLeaderboardScores") {
        self.defaults = defaults
        self.key = key
    }

    func load(for playerID: String) -> Int? {
        loadAll()[playerID]
    }

    func save(_ score: Int?, for playerID: String) {
        var all = loadAll()
        all[playerID] = score
        if all.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(try? JSONEncoder().encode(all), forKey: key)
        }
    }

    private func loadAll() -> [String: Int] {
        defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([String: Int].self, from: $0)
        } ?? [:]
    }
}

@MainActor
@Observable
final class GameCenterModel: NSObject {
    static let activityID = "com.yazdanra.minimatch.play"
    static let leaderboardID = "com.yazdanra.minimatch.wins"
    static let dailyLeaderboardID = "com.yazdanra.minimatch.dailyGlobalWins"
    static let leaderboardMaximumScore: UInt64 = 999_999_999

    private let isEnabled: Bool
    private let achievementPendingStore: any AchievementPendingPersisting
    private let leaderboardScorePendingStore: any LeaderboardScorePendingPersisting
    private let dailyLeaderboardScorePendingStore: any LeaderboardScorePendingPersisting
    private var started = false
    private var listenerIsRegistered = false
    private var reportingPlayerID: String?
    private var dailyReportingSession = PlayerScopedGeneration()
    private weak var gameModel: GameModel?
    private var match: GKMatch?
    private var expectedPlayerCount = 0
    private var connectedPlayerCount = 0
    private var createsTable = false
    private var hostPlayerID: String?
    private var joinCode: String?
    private var isJoiningTable = false
    private var backendPlayers = [String: GKPlayer]()
    private var activity: GKGameActivity?
    private var pendingAchievementIDs = Set<String>()
    private var completedAchievementIDs = Set<String>()
    private var reportingAchievementIDs = Set<String>()
    private var pendingLeaderboardScore = PendingLeaderboardScore()
    private var pendingDailyLeaderboardScore = PendingLeaderboardScore()
    private var isReportingLeaderboardScore = false
    private var isReportingDailyLeaderboardScore = false
    private var dailyLeaderboardLoadGeneration = 0
    private var activityStartGate = ActivityStartGate()

    var authentication: GameCenterAuthentication?
    var matchmaking: GameCenterMatchmaking?
    private(set) var isAuthenticated = false
    private(set) var authenticatedTeamPlayerID: String?
    private(set) var displayName = ""
    private(set) var avatarImage: UIImage?
    private(set) var playerImages = [String: UIImage]()
    private(set) var canShareActivity = false
    private(set) var isMultiplayerRestricted = false
    private(set) var restrictionIsResolved: Bool
    private(set) var errorMessage = ""
    private(set) var dailyLeaderboardEntries = [DailyLeaderboardEntry]()
    private(set) var dailyLocalLeaderboardEntry: DailyLeaderboardEntry?
    private(set) var isLoadingDailyLeaderboard = false
    private(set) var dailyLeaderboardErrorMessage: String?
    var isShowingError = false
    var isStartingActivity: Bool { activityStartGate.isActive }
    var isPreparingLobby: Bool {
        guard match != nil else { return false }
        return expectedPlayerCount > 0
            || (gameModel?.table?.players.count ?? 0) < connectedPlayerCount + 1
    }
    var isTransitioningPlayerSession: Bool {
        gameModel?.isEndingGameCenterSession == true
    }

    init(
        isEnabled: Bool = true,
        achievementPendingStore: any AchievementPendingPersisting =
            UserDefaultsAchievementPendingStore(),
        leaderboardScorePendingStore: any LeaderboardScorePendingPersisting =
            UserDefaultsLeaderboardScorePendingStore(),
        dailyLeaderboardScorePendingStore: any LeaderboardScorePendingPersisting =
            UserDefaultsLeaderboardScorePendingStore(
                key: "pendingGameCenterDailyLeaderboardScores"
            )
    ) {
        self.isEnabled = isEnabled
        self.achievementPendingStore = achievementPendingStore
        self.leaderboardScorePendingStore = leaderboardScorePendingStore
        self.dailyLeaderboardScorePendingStore = dailyLeaderboardScorePendingStore
        restrictionIsResolved = !isEnabled
        super.init()
    }

    func authenticate() {
        guard isEnabled, !started else { return }
        started = true
        GKAccessPoint.shared.isActive = false
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                self.authentication = viewController.map(GameCenterAuthentication.init)
                self.refreshLocalPlayerIdentity()
                self.isMultiplayerRestricted = GKLocalPlayer.local.isMultiplayerGamingRestricted
                self.restrictionIsResolved = viewController == nil
                if self.isAuthenticated {
                    self.registerListener()
                    await self.refreshProfile()
                } else {
                    self.endMatch()
                    self.displayName = ""
                    self.avatarImage = nil
                }
            }
        }
    }

    func attach(to gameModel: GameModel) {
        self.gameModel = gameModel
        gameModel.roundResultHandler = { [weak self] table, playerID in
            self?.reportRoundResult(for: table, currentPlayerID: playerID)
        }
    }

    func startActivity() {
        guard authorizeMatchmaking(), activityStartGate.begin() else { return }
        Task {
            defer { activityStartGate.end() }
            do {
                let definitions = try await GKGameActivityDefinition.loadGameActivityDefinitions(
                    IDs: [Self.activityID]
                )
                guard let definition = definitions.first else {
                    throw GameCenterError.activityUnavailable
                }
                let activity = try GKGameActivity.start(definition: definition)
                guard await enter(activity: activity) else {
                    activity.end()
                    return
                }
                presentMatchmaking(for: activity)
            } catch {
                startMatchmaking()
            }
        }
    }

    func startMatchmaking() {
        startMatchmaking(with: nil)
    }

    func showActivity() {
        guard let activity else { return }
        Task {
            await GKAccessPoint.shared.trigger(gameActivity: activity)
        }
    }

    func joinActivity(code: String) {
        guard authorizeMatchmaking(), activityStartGate.begin() else { return }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard GKGameActivity.isValidPartyCode(code) else {
            activityStartGate.end()
            showError(String(localized: "Enter a valid Game Center party code."))
            return
        }
        Task {
            defer { activityStartGate.end() }
            do {
                let definitions = try await GKGameActivityDefinition.loadGameActivityDefinitions(
                    IDs: [Self.activityID]
                )
                guard let definition = definitions.first else {
                    throw GameCenterError.activityUnavailable
                }
                let activity = try GKGameActivity.start(
                    definition: definition,
                    partyCode: code
                )
                guard await enter(activity: activity) else {
                    activity.end()
                    return
                }
                presentMatchmaking(for: activity)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func setAccessPointActive(_ isActive: Bool) {
        let accessPoint = GKAccessPoint.shared
        accessPoint.location = .topLeading
        accessPoint.isActive = isActive && isAuthenticated
    }

    private func enter(activity: GKGameActivity) async -> Bool {
        guard activity.activityDefinition.identifier == Self.activityID,
              let code = activity.partyCode,
              GKGameActivity.isValidPartyCode(code),
              let gameModel
        else {
            showError(String(localized: "This Game Center activity is unavailable."))
            return false
        }
        if gameModel.table?.joinCode == code {
            self.activity = activity
            canShareActivity = true
            return true
        }
        guard authorizeMatchmaking() else { return false }
        do {
            let identity = try await identityVerification()
            guard await gameModel.enterActivity(
                code: code,
                displayName: displayName,
                avatarID: randomAvatarID(),
                gameCenterIdentity: identity
            ) else {
                return false
            }
            self.activity?.end()
            self.activity = activity
            canShareActivity = true
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func presentMatchmaking(for activity: GKGameActivity) {
        guard gameModel?.isHost == true,
              let request = activity.makeMatchRequest()
        else {
            return
        }
        request.inviteMessage = String(localized: "Join my Mini Match game.")
        guard let viewController = GKMatchmakerViewController(matchRequest: request) else {
            return
        }
        viewController.matchmakingMode = .inviteOnly
        presentMatchmaking(
            viewController,
            createsTable: true,
            hostPlayerID: GKLocalPlayer.local.gamePlayerID
        )
    }

    private func startActivity(partyCode: String) async {
        guard GKGameActivity.isValidPartyCode(partyCode) else { return }
        do {
            let definitions = try await GKGameActivityDefinition.loadGameActivityDefinitions(
                IDs: [Self.activityID]
            )
            guard let definition = definitions.first else { return }
            activity?.end()
            activity = try GKGameActivity.start(
                definition: definition,
                partyCode: partyCode
            )
            canShareActivity = true
        } catch {
            // Game Activity discovery is additive; the current match remains playable.
        }
    }

    private func startMatchmaking(with recipients: [GKPlayer]?) {
        guard authorizeMatchmaking() else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = GKMatchRequest.maxPlayersAllowedForMatch(of: .peerToPeer)
        request.inviteMessage = String(localized: "Join my Mini Match game.")
        request.recipients = recipients
        guard let viewController = GKMatchmakerViewController(matchRequest: request) else {
            showError(String(localized: "Game Center matchmaking is unavailable."))
            return
        }
        viewController.matchmakingMode = .inviteOnly
        presentMatchmaking(
            viewController,
            createsTable: true,
            hostPlayerID: GKLocalPlayer.local.gamePlayerID
        )
    }

    private func authorizeMatchmaking() -> Bool {
        guard gameModel?.screen == .home,
              gameModel?.isEndingGameCenterSession != true
        else {
            return false
        }
        guard restrictionIsResolved, !isMultiplayerRestricted else {
            showError(String(localized: "Multiplayer is unavailable because of Screen Time settings."))
            return false
        }
        return isAuthenticated && match == nil && matchmaking == nil
    }

    private func presentMatchmaking(
        _ viewController: GKMatchmakerViewController,
        createsTable: Bool,
        hostPlayerID: String
    ) {
        viewController.matchmakerDelegate = self
        matchmaking = GameCenterMatchmaking(
            viewController: viewController,
            createsTable: createsTable,
            hostPlayerID: hostPlayerID
        )
    }

    func dismissMatchmaking() {
        matchmaking?.viewController.matchmakerDelegate = nil
        matchmaking = nil
    }

    func endMatch() {
        matchmaking?.viewController.matchmakerDelegate = nil
        matchmaking = nil
        endControlMatch()
        activity?.end()
        activity = nil
        canShareActivity = false
        bindReportingPlayer(nil)
    }

    private func endControlMatch() {
        match?.delegate = nil
        match?.disconnect()
        match = nil
        updateMatchRoster(from: nil)
        createsTable = false
        hostPlayerID = nil
        joinCode = nil
        isJoiningTable = false
        backendPlayers.removeAll()
        playerImages.removeAll()
    }

    func identityVerification() async throws -> GameCenterIdentityDTO? {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else {
            bindReportingPlayer(nil)
            bindDailyReportingPlayer(nil)
            return nil
        }
        let playerID = player.gamePlayerID
        bindReportingPlayer(playerID)
        let items: GameCenterVerificationItems = try await withCheckedThrowingContinuation {
            continuation in
            player.fetchItems(forIdentityVerificationSignature: {
                publicKeyURL,
                signature,
                salt,
                timestamp,
                error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let publicKeyURL, let signature, let salt {
                    continuation.resume(returning: GameCenterVerificationItems(
                        publicKeyURL: publicKeyURL,
                        signature: signature,
                        salt: salt,
                        timestamp: timestamp
                    ))
                } else {
                    continuation.resume(throwing: GameCenterError.invalidIdentity)
                }
            })
        }
        guard GKLocalPlayer.local.isAuthenticated,
              GKLocalPlayer.local.gamePlayerID == playerID
        else {
            throw GameCenterError.accountChanged
        }
        return GameCenterIdentityDTO(
            teamPlayerId: player.teamPlayerID,
            publicKeyUrl: items.publicKeyURL.absoluteString,
            signature: items.signature,
            salt: items.salt,
            timestamp: String(items.timestamp)
        )
    }

    func requiredIdentityVerification() async throws -> GameCenterIdentityDTO {
        guard let identity = try await identityVerification() else {
            throw GameCenterError.authenticationRequired
        }
        return identity
    }

    func reportDailyWins(_ total: UInt64, verifiedBy identity: GameCenterIdentityDTO) {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated, player.teamPlayerID == identity.teamPlayerId else {
            bindDailyReportingPlayer(player.isAuthenticated ? player.gamePlayerID : nil)
            return
        }
        bindDailyReportingPlayer(player.gamePlayerID)
        pendingDailyLeaderboardScore.enqueue(total, maximum: Self.leaderboardMaximumScore)
        persistPendingDailyLeaderboardScore()
        reportPendingDailyLeaderboardScore(for: player)
    }

    func loadDailyLeaderboard() async {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else {
            bindDailyReportingPlayer(nil)
            dailyLeaderboardErrorMessage = GameCenterError.authenticationRequired.errorDescription
            return
        }

        let playerID = player.gamePlayerID
        bindDailyReportingPlayer(playerID)
        dailyLeaderboardLoadGeneration &+= 1
        let generation = dailyLeaderboardLoadGeneration
        isLoadingDailyLeaderboard = true
        dailyLeaderboardErrorMessage = nil

        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(
                IDs: [Self.dailyLeaderboardID]
            )
            guard dailyLeaderboardLoadIsCurrent(generation, playerID: playerID) else {
                refreshLocalPlayerIdentity()
                return
            }
            guard let leaderboard = leaderboards.first(where: {
                $0.baseLeaderboardID == Self.dailyLeaderboardID
            }) else {
                throw GameCenterError.leaderboardUnavailable
            }
            let (localPlayerEntry, entries, _) = try await leaderboard.loadEntries(
                for: .global,
                timeScope: .allTime,
                range: NSRange(location: 1, length: 100)
            )
            guard dailyLeaderboardLoadIsCurrent(generation, playerID: playerID) else {
                refreshLocalPlayerIdentity()
                return
            }
            dailyLeaderboardEntries = entries.map {
                DailyLeaderboardEntry($0, localPlayerID: playerID)
            }
            dailyLocalLeaderboardEntry = localPlayerEntry.map {
                DailyLeaderboardEntry($0, localPlayerID: playerID)
            }
        } catch {
            guard dailyLeaderboardLoadIsCurrent(generation, playerID: playerID) else {
                refreshLocalPlayerIdentity()
                return
            }
            dailyLeaderboardErrorMessage = error.localizedDescription
        }

        guard dailyLeaderboardLoadIsCurrent(generation, playerID: playerID) else { return }
        isLoadingDailyLeaderboard = false
    }

    private func dailyLeaderboardLoadIsCurrent(_ generation: Int, playerID: String) -> Bool {
        generation == dailyLeaderboardLoadGeneration
            && dailyReportingSession.playerID == playerID
            && GKLocalPlayer.local.isAuthenticated
            && GKLocalPlayer.local.gamePlayerID == playerID
    }

    func dismissAuthentication() {
        authentication = nil
        refreshRestrictions()
    }

    func refreshRestrictions() {
        guard isEnabled, started, authentication == nil else { return }
        refreshLocalPlayerIdentity()
        isMultiplayerRestricted = GKLocalPlayer.local.isMultiplayerGamingRestricted
        restrictionIsResolved = true
        guard isAuthenticated else {
            endMatch()
            displayName = ""
            avatarImage = nil
            return
        }
        Task {
            await refreshProfile()
        }
    }

    private func refreshLocalPlayerIdentity() {
        let player = GKLocalPlayer.local
        isAuthenticated = player.isAuthenticated
        authenticatedTeamPlayerID = isAuthenticated ? player.teamPlayerID : nil
        bindReportingPlayer(isAuthenticated ? player.gamePlayerID : nil)
        bindDailyReportingPlayer(isAuthenticated ? player.gamePlayerID : nil)
        if isAuthenticated {
            reportPendingAchievements(for: player)
            reportPendingLeaderboardScore(for: player)
            reportPendingDailyLeaderboardScore(for: player)
        }
    }

    private func registerListener() {
        guard !listenerIsRegistered else { return }
        GKLocalPlayer.local.register(self)
        listenerIsRegistered = true
    }

    private func accept(
        _ foundMatch: GKMatch,
        createsTable: Bool,
        hostPlayerID: String
    ) {
        matchmaking?.viewController.matchmakerDelegate = nil
        matchmaking = nil
        match = foundMatch
        updateMatchRoster(from: foundMatch)
        self.createsTable = createsTable
        self.hostPlayerID = hostPlayerID
        foundMatch.delegate = self
        send(.ready, in: foundMatch)
        if createsTable {
            if let code = gameModel?.table?.joinCode {
                joinCode = code
                registerLocalPlayer(in: foundMatch)
            } else {
                Task {
                    await createBackendTable(for: foundMatch)
                }
            }
        }
    }

    private func createBackendTable(for match: GKMatch) async {
        guard self.match === match, let gameModel else { return }
        do {
            let identity = try await identityVerification()
            guard await gameModel.createTable(
                name: "Mini Match",
                displayName: displayName,
                avatarID: randomAvatarID(),
                gameCenterIdentity: identity
            ), self.match === match, let code = gameModel.table?.joinCode
            else {
                await abort(match, notifyPeers: true)
                return
            }
            joinCode = code
            await startActivity(partyCode: code)
            guard send(.session(code), in: match) else {
                await abort(match, notifyPeers: false)
                return
            }
            registerLocalPlayer(in: match)
        } catch {
            showError(error.localizedDescription)
            await abort(match, notifyPeers: true)
        }
    }

    private func joinBackendTable(code: String, in match: GKMatch) async {
        guard self.match === match, !createsTable, !isJoiningTable,
              let gameModel, gameModel.screen == .home
        else {
            return
        }
        isJoiningTable = true
        defer { isJoiningTable = false }
        do {
            let identity = try await identityVerification()
            guard await gameModel.joinTable(
                code: code,
                displayName: displayName,
                avatarID: randomAvatarID(),
                gameCenterIdentity: identity
            ), self.match === match
            else {
                await abort(match, notifyPeers: true)
                return
            }
            await startActivity(partyCode: code)
            registerLocalPlayer(in: match)
        } catch {
            showError(error.localizedDescription)
            await abort(match, notifyPeers: true)
        }
    }

    private func registerLocalPlayer(in match: GKMatch) {
        guard let playerID = gameModel?.currentPlayerID else { return }
        backendPlayers[playerID] = GKLocalPlayer.local
        if let avatarImage {
            playerImages[playerID] = avatarImage
        }
        send(.joined(playerID), in: match)
        send(.ready, in: match)
    }

    private func register(
        backendPlayerID: String,
        gameCenterPlayer: GKPlayer,
        in match: GKMatch
    ) async {
        guard self.match === match, let gameModel else { return }
        await gameModel.refreshTable()
        guard gameModel.table?.players.contains(where: { $0.id == backendPlayerID }) == true else {
            return
        }
        if let existingPlayer = backendPlayers[backendPlayerID],
           existingPlayer.gamePlayerID != gameCenterPlayer.gamePlayerID {
            backendPlayers[backendPlayerID] = nil
            playerImages[backendPlayerID] = nil
            return
        }
        if let conflictingPlayer = backendPlayers.first(where: {
            $0.key != backendPlayerID
                && $0.value.gamePlayerID == gameCenterPlayer.gamePlayerID
        }) {
            backendPlayers[conflictingPlayer.key] = nil
            playerImages[conflictingPlayer.key] = nil
            return
        }
        backendPlayers[backendPlayerID] = gameCenterPlayer
        guard let image = try? await gameCenterPlayer.loadPhoto(for: .small),
              self.match === match,
              backendPlayers[backendPlayerID]?.gamePlayerID == gameCenterPlayer.gamePlayerID
        else {
            return
        }
        playerImages[backendPlayerID] = image
    }

    private func receive(_ data: Data, from player: GKPlayer, in match: GKMatch) async {
        guard self.match === match, data.count <= 4_096,
              let message = try? JSONDecoder().decode(GameCenterMatchMessage.self, from: data)
        else {
            return
        }
        updateMatchRoster(from: match)
        switch message {
        case .ready:
            if createsTable, let joinCode {
                send(.session(joinCode), to: [player], in: match)
            }
            if let playerID = gameModel?.currentPlayerID {
                send(.joined(playerID), to: [player], in: match)
            }
        case let .session(code):
            guard !createsTable, player.gamePlayerID == hostPlayerID else { return }
            await joinBackendTable(code: code, in: match)
        case let .joined(playerID):
            await register(backendPlayerID: playerID, gameCenterPlayer: player, in: match)
        case .abort:
            if gameModel?.screen == .home {
                showError(String(localized: "A player couldn’t join the Game Center match."))
                endMatch()
            } else {
                endControlMatch()
            }
        }
    }

    @discardableResult
    private func send(
        _ message: GameCenterMatchMessage,
        to players: [GKPlayer]? = nil,
        in match: GKMatch
    ) -> Bool {
        guard self.match === match, let data = try? JSONEncoder().encode(message) else {
            return false
        }
        do {
            if let players {
                try match.send(data, to: players, dataMode: .reliable)
            } else {
                try match.sendData(toAllPlayers: data, with: .reliable)
            }
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func abort(_ match: GKMatch, notifyPeers: Bool) async {
        if notifyPeers {
            send(.abort, in: match)
        }
        await leaveBackendTableAndEndMatch()
    }

    private func leaveBackendTableAndEndMatch() async {
        if let gameModel, gameModel.screen != .home {
            await gameModel.leaveTable()
            if gameModel.screen != .home {
                gameModel.discardSession()
            }
        }
        endMatch()
    }

    private func randomAvatarID() -> String {
        PlayerAvatar.allCases.randomElement()?.rawValue ?? PlayerAvatar.spark.rawValue
    }

    private func updateMatchRoster(from match: GKMatch?) {
        expectedPlayerCount = match?.expectedPlayerCount ?? 0
        connectedPlayerCount = match?.players.count ?? 0
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func refreshProfile() async {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return }
        let playerID = player.gamePlayerID
        displayName = player.displayName
        let image = try? await player.loadPhoto(for: .small)
        guard GKLocalPlayer.local.isAuthenticated,
              GKLocalPlayer.local.gamePlayerID == playerID
        else {
            return
        }
        avatarImage = image
        if let image, let backendPlayerID = gameModel?.currentPlayerID,
           backendPlayers[backendPlayerID]?.gamePlayerID == playerID {
            playerImages[backendPlayerID] = image
        }
    }

    private func reportRoundResult(for table: GameTable, currentPlayerID: String) {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated,
              gameModel?.gameCenterTeamPlayerID == player.teamPlayerID
        else {
            return
        }
        bindReportingPlayer(player.gamePlayerID)
        pendingAchievementIDs.formUnion(GameCenterAchievement.earned(
            in: table,
            currentPlayerID: currentPlayerID
        ).map(\.rawValue))
        persistPendingAchievements()
        reportPendingAchievements(for: player)
        if table.lastResult?.winnerPlayerID == currentPlayerID,
           let value = table.lastResult?.localPlayerLeaderboardScore {
            pendingLeaderboardScore.enqueue(value, maximum: Self.leaderboardMaximumScore)
            persistPendingLeaderboardScore()
            reportPendingLeaderboardScore(for: player)
        }
    }

    private func reportPendingAchievements(for player: GKLocalPlayer) {
        guard player.isAuthenticated, reportingPlayerID == player.gamePlayerID else { return }
        let pending = pendingAchievementIDs
            .subtracting(completedAchievementIDs)
            .subtracting(reportingAchievementIDs)
        guard !pending.isEmpty else { return }

        reportingAchievementIDs.formUnion(pending)
        let playerID = player.gamePlayerID
        Task {
            let achievements = pending.map {
                let achievement = GKAchievement(identifier: $0)
                achievement.percentComplete = 100
                achievement.showsCompletionBanner = true
                return achievement
            }
            do {
                try await GKAchievement.report(achievements)
                guard GKLocalPlayer.local.gamePlayerID == playerID else { return }
                completedAchievementIDs.formUnion(pending)
                reportingAchievementIDs.subtract(pending)
                pendingAchievementIDs.subtract(pending)
                persistPendingAchievements()
            } catch {
                guard GKLocalPlayer.local.gamePlayerID == playerID else { return }
                reportingAchievementIDs.subtract(pending)
            }
        }
    }

    private func reportPendingLeaderboardScore(for player: GKLocalPlayer) {
        guard player.isAuthenticated,
              reportingPlayerID == player.gamePlayerID,
              let score = pendingLeaderboardScore.value,
              !isReportingLeaderboardScore
        else {
            return
        }

        isReportingLeaderboardScore = true
        let playerID = player.gamePlayerID
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: player,
                    leaderboardIDs: [Self.leaderboardID]
                )
                guard GKLocalPlayer.local.gamePlayerID == playerID else { return }
                if pendingLeaderboardScore.value == score {
                    pendingLeaderboardScore.complete(score)
                    persistPendingLeaderboardScore()
                }
                isReportingLeaderboardScore = false
                reportPendingLeaderboardScore(for: player)
            } catch {
                guard GKLocalPlayer.local.gamePlayerID == playerID else { return }
                isReportingLeaderboardScore = false
            }
        }
    }

    private func reportPendingDailyLeaderboardScore(for player: GKLocalPlayer) {
        guard player.isAuthenticated,
              dailyReportingSession.playerID == player.gamePlayerID,
              let score = pendingDailyLeaderboardScore.value,
              !isReportingDailyLeaderboardScore
        else {
            return
        }

        isReportingDailyLeaderboardScore = true
        let playerID = player.gamePlayerID
        let reportingGeneration = dailyReportingSession.value
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: player,
                    leaderboardIDs: [Self.dailyLeaderboardID]
                )
                guard dailyReportingSession.matches(reportingGeneration, playerID: playerID),
                      GKLocalPlayer.local.isAuthenticated,
                      GKLocalPlayer.local.gamePlayerID == playerID
                else {
                    refreshLocalPlayerIdentity()
                    return
                }
                if pendingDailyLeaderboardScore.value == score {
                    pendingDailyLeaderboardScore.complete(score)
                    persistPendingDailyLeaderboardScore()
                }
                isReportingDailyLeaderboardScore = false
                reportPendingDailyLeaderboardScore(for: player)
            } catch {
                guard dailyReportingSession.matches(reportingGeneration, playerID: playerID),
                      GKLocalPlayer.local.isAuthenticated,
                      GKLocalPlayer.local.gamePlayerID == playerID
                else {
                    refreshLocalPlayerIdentity()
                    return
                }
                isReportingDailyLeaderboardScore = false
            }
        }
    }

    private func bindReportingPlayer(_ playerID: String?) {
        guard reportingPlayerID != playerID else { return }
        reportingPlayerID = playerID
        pendingAchievementIDs = playerID.map { achievementPendingStore.load(for: $0) } ?? []
        pendingLeaderboardScore = PendingLeaderboardScore(
            playerID.flatMap { leaderboardScorePendingStore.load(for: $0) }
        )
        completedAchievementIDs.removeAll()
        reportingAchievementIDs.removeAll()
        isReportingLeaderboardScore = false
    }

    private func bindDailyReportingPlayer(_ playerID: String?) {
        guard dailyReportingSession.bind(to: playerID) else { return }
        pendingDailyLeaderboardScore = PendingLeaderboardScore(
            playerID.flatMap { dailyLeaderboardScorePendingStore.load(for: $0) }
        )
        isReportingDailyLeaderboardScore = false
        dailyLeaderboardLoadGeneration &+= 1
        dailyLeaderboardEntries.removeAll()
        dailyLocalLeaderboardEntry = nil
        isLoadingDailyLeaderboard = false
        dailyLeaderboardErrorMessage = nil
    }

    private func persistPendingAchievements() {
        guard let reportingPlayerID else { return }
        achievementPendingStore.save(pendingAchievementIDs, for: reportingPlayerID)
    }

    private func persistPendingLeaderboardScore() {
        guard let reportingPlayerID else { return }
        leaderboardScorePendingStore.save(pendingLeaderboardScore.value, for: reportingPlayerID)
    }

    private func persistPendingDailyLeaderboardScore() {
        guard let playerID = dailyReportingSession.playerID else { return }
        dailyLeaderboardScorePendingStore.save(
            pendingDailyLeaderboardScore.value,
            for: playerID
        )
    }

}

extension GameCenterModel: @preconcurrency GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(
        _ viewController: GKMatchmakerViewController
    ) {
        let shouldLeaveActivity = matchmaking?.createsTable == true
            && gameModel?.screen == .lobby
        dismissMatchmaking()
        if shouldLeaveActivity {
            Task {
                await leaveBackendTableAndEndMatch()
            }
        }
    }

    func matchmakerViewController(
        _ viewController: GKMatchmakerViewController,
        didFailWithError error: any Error
    ) {
        dismissMatchmaking()
        showError(error.localizedDescription)
    }

    func matchmakerViewController(
        _ viewController: GKMatchmakerViewController,
        didFind match: GKMatch
    ) {
        guard let matchmaking, matchmaking.viewController === viewController else {
            match.disconnect()
            return
        }
        accept(
            match,
            createsTable: matchmaking.createsTable,
            hostPlayerID: matchmaking.hostPlayerID
        )
    }
}

extension GameCenterModel: GKMatchDelegate {
    nonisolated func match(
        _ match: GKMatch,
        didReceive data: Data,
        fromRemotePlayer player: GKPlayer
    ) {
        let matchID = ObjectIdentifier(match)
        let playerID = player.gamePlayerID
        Task { @MainActor [weak self] in
            guard let self, let match = self.match,
                  ObjectIdentifier(match) == matchID,
                  let player = match.players.first(where: { $0.gamePlayerID == playerID })
            else {
                return
            }
            await receive(data, from: player, in: match)
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        let matchID = ObjectIdentifier(match)
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, let match = self.match, ObjectIdentifier(match) == matchID else {
                return
            }
            if gameModel?.screen == .home {
                if let message {
                    showError(message)
                }
                endMatch()
            } else {
                endControlMatch()
            }
        }
    }

    nonisolated func match(
        _ match: GKMatch,
        player: GKPlayer,
        didChange state: GKPlayerConnectionState
    ) {
        let matchID = ObjectIdentifier(match)
        let disconnected = state == .disconnected
        Task { @MainActor [weak self] in
            guard let self, let match = self.match,
                  ObjectIdentifier(match) == matchID
            else {
                return
            }
            updateMatchRoster(from: match)
            guard disconnected else { return }
            if gameModel?.screen == .home {
                showError(String(localized: "A player disconnected from the Game Center match."))
                endMatch()
            } else {
                endControlMatch()
            }
        }
    }
}

extension GameCenterModel: @preconcurrency GKLocalPlayerListener {
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        guard authorizeMatchmaking() else { return }
        guard let viewController = GKMatchmakerViewController(invite: invite) else {
            showError(String(localized: "Game Center matchmaking is unavailable."))
            return
        }
        presentMatchmaking(
            viewController,
            createsTable: false,
            hostPlayerID: invite.sender.gamePlayerID
        )
    }

    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipientPlayers: [GKPlayer]) {
        startMatchmaking(with: recipientPlayers)
    }

    func player(_ player: GKPlayer, wantsToPlay activity: GKGameActivity) async -> Bool {
        guard await enter(activity: activity) else { return false }
        presentMatchmaking(for: activity)
        return true
    }
}

extension GameCenterModel {
    static func preview(isAuthenticated: Bool = true) -> GameCenterModel {
        let model = GameCenterModel(isEnabled: false)
        model.isAuthenticated = isAuthenticated
        model.displayName = isAuthenticated ? "Maya" : ""
        return model
    }
}

private struct GameCenterVerificationItems {
    let publicKeyURL: URL
    let signature: Data
    let salt: Data
    let timestamp: UInt64
}

private enum GameCenterMatchMessage: Codable {
    case ready
    case session(String)
    case joined(String)
    case abort
}

private enum GameCenterError: LocalizedError {
    case activityUnavailable
    case accountChanged
    case authenticationRequired
    case invalidIdentity
    case leaderboardUnavailable

    var errorDescription: String? {
        switch self {
        case .activityUnavailable:
            String(localized: "This Game Center activity is unavailable.")
        case .accountChanged:
            String(localized: "The Game Center account changed. Try again.")
        case .authenticationRequired:
            String(localized: "Sign in to Game Center to continue.")
        case .invalidIdentity:
            String(localized: "Game Center couldn’t verify this player. Try again.")
        case .leaderboardUnavailable:
            String(localized: "The Daily Wins leaderboard is unavailable.")
        }
    }
}

enum GameCenterAchievement: String, CaseIterable {
    case firstWin = "com.yazdanra.minimatch.achievement.firstWin"
    // Retained so a report queued before positive-only picks can still complete.
    case zeroWin = "com.yazdanra.minimatch.achievement.zeroWin"
    case fourPlayerWin = "com.yazdanra.minimatch.achievement.fourPlayerWin"
    case pickFourWin = "com.yazdanra.minimatch.achievement.pickFourWin"
    case pickEightWin = "com.yazdanra.minimatch.achievement.pickEightWin"
    case pickSixteenWin = "com.yazdanra.minimatch.achievement.pickSixteenWin"
    case twoWinStreak = "com.yazdanra.minimatch.achievement.twoWinStreak"
    case fourWinStreak = "com.yazdanra.minimatch.achievement.fourWinStreak"
    case sixteenRoundWins = "com.yazdanra.minimatch.achievement.sixteenRoundWins"
    case thirtyTwoRoundWins = "com.yazdanra.minimatch.achievement.thirtyTwoRoundWins"
    case sixtyFourRoundWins = "com.yazdanra.minimatch.achievement.sixtyFourRoundWins"
    case eightPlayerWin = "com.yazdanra.minimatch.achievement.eightPlayerWin"
    case sixteenPlayerWin = "com.yazdanra.minimatch.achievement.sixteenPlayerWin"
    case eightPlayerRound = "com.yazdanra.minimatch.achievement.eightPlayerRound"
    case sixteenPlayerRound = "com.yazdanra.minimatch.achievement.sixteenPlayerRound"

    static func earned(in table: GameTable, currentPlayerID: String) -> Set<Self> {
        guard let result = table.lastResult,
              let selection = result.selections.first(where: { $0.playerID == currentPlayerID })
        else {
            return []
        }

        let playerCount = result.selections.count
        var earned = Set<Self>()
        if playerCount >= 8 {
            earned.insert(.eightPlayerRound)
        }
        if playerCount >= 16 {
            earned.insert(.sixteenPlayerRound)
        }

        guard result.winnerPlayerID == currentPlayerID else { return earned }

        earned.insert(.firstWin)
        switch selection.pick {
        case 4: earned.insert(.pickFourWin)
        case 8: earned.insert(.pickEightWin)
        case 16: earned.insert(.pickSixteenWin)
        default: break
        }
        if playerCount >= 4 {
            earned.insert(.fourPlayerWin)
        }
        if playerCount >= 8 {
            earned.insert(.eightPlayerWin)
        }
        if playerCount >= 16 {
            earned.insert(.sixteenPlayerWin)
        }
        earned.formUnion(result.winnerAchievementIDs.compactMap(Self.init(rawValue:)))
        return earned
    }
}
