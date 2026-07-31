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

@MainActor
@Observable
final class GameCenterModel: NSObject {
    static let winsLeaderboardID = "com.yazdanra.minimatch.wins"

    private let isEnabled: Bool
    private var started = false
    private var listenerIsRegistered = false
    private var matchPlayerID: String?
    private weak var gameModel: GameModel?
    private var match: GKMatch?
    private var matchPlayerCount = 0
    private var createsTable = false
    private var hostPlayerID: String?
    private var joinCode: String?
    private var isJoiningTable = false
    private var backendPlayers = [String: GKPlayer]()

    var authentication: GameCenterAuthentication?
    var matchmaking: GameCenterMatchmaking?
    private(set) var isAuthenticated = false
    private(set) var displayName = ""
    private(set) var avatarImage: UIImage?
    private(set) var playerImages = [String: UIImage]()
    private(set) var isMultiplayerRestricted = false
    private(set) var restrictionIsResolved: Bool
    private(set) var errorMessage = ""
    var isShowingError = false

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
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
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.isMultiplayerRestricted = GKLocalPlayer.local.isMultiplayerGamingRestricted
                self.restrictionIsResolved = viewController == nil
                if self.isAuthenticated {
                    self.registerListener()
                    await self.refreshProfile()
                    await self.syncWins()
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
    }

    func startMatchmaking() {
        guard isAuthenticated, !isMultiplayerRestricted, match == nil else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = GKMatchRequest.maxPlayersAllowedForMatch(of: .peerToPeer)
        request.inviteMessage = String(localized: "Join my Mini Match game.")
        guard let viewController = GKMatchmakerViewController(matchRequest: request) else {
            showError(String(localized: "Game Center matchmaking is unavailable."))
            return
        }
        viewController.matchmakingMode = .inviteOnly
        viewController.matchmakerDelegate = self
        matchmaking = GameCenterMatchmaking(
            viewController: viewController,
            createsTable: true,
            hostPlayerID: GKLocalPlayer.local.gamePlayerID
        )
    }

    func dismissMatchmaking() {
        matchmaking?.viewController.matchmakerDelegate = nil
        matchmaking = nil
    }

    func endMatch() {
        matchmaking?.viewController.matchmakerDelegate = nil
        matchmaking = nil
        match?.delegate = nil
        match?.disconnect()
        match = nil
        matchPlayerCount = 0
        createsTable = false
        hostPlayerID = nil
        joinCode = nil
        isJoiningTable = false
        backendPlayers.removeAll()
        playerImages.removeAll()
    }

    func showProfile() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .localPlayerProfile) {}
    }

    func showLeaderboard() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }

    func identityVerification() async throws -> GameCenterIdentityDTO? {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else {
            matchPlayerID = nil
            return nil
        }
        let playerID = player.gamePlayerID
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
        matchPlayerID = playerID
        return GameCenterIdentityDTO(
            teamPlayerId: player.teamPlayerID,
            publicKeyUrl: items.publicKeyURL.absoluteString,
            signature: items.signature,
            salt: items.salt,
            timestamp: String(items.timestamp)
        )
    }

    func reportMatchWin(_ win: CompletedMatchWin) async {
        guard let playerID = matchPlayerID else { return }
        setPendingWins(max(pendingWins(for: playerID) ?? 0, win.lifetimeWins), for: playerID)
        if GKLocalPlayer.local.isAuthenticated,
           GKLocalPlayer.local.gamePlayerID == playerID {
            await syncWins()
        }
    }

    func dismissAuthentication() {
        authentication = nil
        refreshRestrictions()
    }

    func refreshRestrictions() {
        guard isEnabled, started, authentication == nil else { return }
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
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
            await syncWins()
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
        matchPlayerCount = foundMatch.players.count + foundMatch.expectedPlayerCount + 1
        self.createsTable = createsTable
        self.hostPlayerID = hostPlayerID
        foundMatch.delegate = self
        send(.ready, in: foundMatch)
        if createsTable {
            Task {
                await createBackendTable(for: foundMatch)
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
            showError(String(localized: "A player couldn’t join the Game Center match."))
            await leaveBackendTableAndEndMatch()
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

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func pendingWins(for playerID: String) -> UInt64? {
        UserDefaults.standard.string(forKey: pendingWinsKey(for: playerID)).flatMap(UInt64.init)
    }

    private func setPendingWins(_ wins: UInt64?, for playerID: String) {
        UserDefaults.standard.set(wins.map(String.init), forKey: pendingWinsKey(for: playerID))
    }

    private func pendingWinsKey(for playerID: String) -> String {
        "GameCenterPendingLifetimeWins.\(playerID)"
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

    private func syncWins() async {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return }
        let playerID = player.gamePlayerID
        guard let wins = pendingWins(for: playerID),
              let score = Int(exactly: wins)
        else {
            return
        }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: player,
                leaderboardIDs: [Self.winsLeaderboardID]
            )
            guard GKLocalPlayer.local.isAuthenticated,
                  GKLocalPlayer.local.gamePlayerID == playerID,
                  pendingWins(for: playerID) == wins
            else {
                return
            }
            setPendingWins(nil, for: playerID)
        } catch {
            // GameKit submission retries the next time authentication or a win refreshes.
        }
    }
}

extension GameCenterModel: @preconcurrency GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(
        _ viewController: GKMatchmakerViewController
    ) {
        dismissMatchmaking()
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
            if let message {
                showError(message)
            }
            await leaveBackendTableAndEndMatch()
        }
    }

    nonisolated func match(
        _ match: GKMatch,
        player: GKPlayer,
        didChange state: GKPlayerConnectionState
    ) {
        guard state == .disconnected else { return }
        let matchID = ObjectIdentifier(match)
        Task { @MainActor [weak self] in
            guard let self, let match = self.match,
                  ObjectIdentifier(match) == matchID,
                  (gameModel?.table?.players.count ?? 0) < matchPlayerCount
            else {
                return
            }
            showError(String(localized: "A player disconnected before the match was ready."))
            await leaveBackendTableAndEndMatch()
        }
    }
}

extension GameCenterModel: @preconcurrency GKLocalPlayerListener {
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        guard isAuthenticated, match == nil,
              let viewController = GKMatchmakerViewController(invite: invite)
        else {
            return
        }
        viewController.matchmakerDelegate = self
        matchmaking = GameCenterMatchmaking(
            viewController: viewController,
            createsTable: false,
            hostPlayerID: invite.sender.gamePlayerID
        )
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
    case accountChanged
    case invalidIdentity

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            String(localized: "The Game Center account changed. Try again.")
        case .invalidIdentity:
            String(localized: "Game Center couldn’t verify this player. Try again.")
        }
    }
}
