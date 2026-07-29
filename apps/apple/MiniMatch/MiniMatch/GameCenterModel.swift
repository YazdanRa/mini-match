import GameKit
import Observation
import SwiftUI

struct GameCenterAuthentication: Identifiable {
    let id = UUID()
    let viewController: UIViewController
}

@MainActor
@Observable
final class GameCenterModel {
    private let isEnabled: Bool
    private var started = false
    private var wantsAccessPoint = false

    var authentication: GameCenterAuthentication?
    private(set) var isAuthenticated = false
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
        GKAccessPoint.shared.location = .topLeading
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
                self.updateAccessPoint()
            }
        }
    }

    func setAccessPointActive(_ active: Bool) {
        wantsAccessPoint = active
        updateAccessPoint()
    }

    func dismissAuthentication() {
        authentication = nil
        refreshRestrictions()
    }

    func refreshRestrictions() {
        guard isEnabled, started, authentication == nil else { return }
        isMultiplayerRestricted = GKLocalPlayer.local.isMultiplayerGamingRestricted
        personalizedCommunicationIsRestricted =
            GKLocalPlayer.local.isPersonalizedCommunicationRestricted
            || GKLocalPlayer.local.isUnderage
        restrictionIsResolved = true
        updateAccessPoint()
    }

    private func updateAccessPoint() {
        guard isEnabled else { return }
        GKAccessPoint.shared.isActive =
            isAuthenticated && wantsAccessPoint && authentication == nil
    }
}

struct GameCenterAuthenticationView: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
