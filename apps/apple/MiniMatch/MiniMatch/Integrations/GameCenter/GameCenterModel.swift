import GameKit
import Observation
import UIKit

struct GameCenterAuthentication: Identifiable {
    let id = UUID()
    let viewController: UIViewController
}

@MainActor
@Observable
final class GameCenterModel {
    static let winsLeaderboardID = "com.yazdanra.minimatch.wins"

    private let isEnabled: Bool
    private var started = false
    private var matchPlayerID: String?

    var authentication: GameCenterAuthentication?
    private(set) var isAuthenticated = false
    private(set) var displayName = ""
    private(set) var avatarImage: UIImage?
    private(set) var isMultiplayerRestricted = false
    private(set) var personalizedCommunicationIsRestricted = false
    private(set) var restrictionIsResolved: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        restrictionIsResolved = !isEnabled
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
                self.personalizedCommunicationIsRestricted =
                    GKLocalPlayer.local.isPersonalizedCommunicationRestricted
                    || GKLocalPlayer.local.isUnderage
                self.restrictionIsResolved = viewController == nil
                if self.isAuthenticated {
                    await self.refreshProfile()
                    await self.syncWins()
                } else {
                    self.displayName = ""
                    self.avatarImage = nil
                }
            }
        }
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
        personalizedCommunicationIsRestricted =
            GKLocalPlayer.local.isPersonalizedCommunicationRestricted
            || GKLocalPlayer.local.isUnderage
        restrictionIsResolved = true
        guard isAuthenticated else {
            displayName = ""
            avatarImage = nil
            return
        }
        Task {
            await refreshProfile()
            await syncWins()
        }
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

private struct GameCenterVerificationItems {
    let publicKeyURL: URL
    let signature: Data
    let salt: Data
    let timestamp: UInt64
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
