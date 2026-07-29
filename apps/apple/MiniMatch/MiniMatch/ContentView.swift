import SwiftUI

struct ContentView: View {
    let model: GameModel
    let gameCenter: GameCenterModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        @Bindable var gameCenter = gameCenter

        ZStack {
            MiniMatchColors.background
                .ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    MiniMatchColors.navy
                        .frame(height: geometry.safeAreaInsets.top)
                    Spacer()
                }
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            switch model.screen {
            case .home:
                HomeView(
                    model: model,
                    multiplayerIsUnavailable: !gameCenter.restrictionIsResolved
                        || gameCenter.isMultiplayerRestricted,
                    multiplayerIsRestricted: gameCenter.isMultiplayerRestricted
                )
            case .lobby:
                LobbyView(
                    model: model,
                    canShareInvites: !gameCenter.personalizedCommunicationIsRestricted
                )
            case .result:
                ResultView(model: model)
            }
        }
        .tint(MiniMatchColors.blueText)
        .onChange(of: model.screen, initial: true) { _, screen in
            gameCenter.setAccessPointActive(screen == .home)
        }
        .onChange(
            of: gameCenter.restrictionIsResolved && !gameCenter.isMultiplayerRestricted,
            initial: true
        ) { _, multiplayerIsAvailable in
            Task {
                await model.setMultiplayerRestricted(!multiplayerIsAvailable)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                gameCenter.refreshRestrictions()
            }
        }
        .fullScreenCover(item: $gameCenter.authentication, onDismiss: {
            gameCenter.dismissAuthentication()
        }) { authentication in
            GameCenterAuthenticationView(viewController: authentication.viewController)
                .ignoresSafeArea()
        }
        .alert(
            "Couldn’t continue",
            isPresented: $model.isShowingError,
            actions: { Button("OK") {} },
            message: { Text(model.errorMessage) }
        )
    }
}
