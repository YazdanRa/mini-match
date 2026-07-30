import AuthenticationServices
import SwiftUI

struct ContentView: View {
    let model: GameModel
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        @Bindable var gameCenter = gameCenter
        @Bindable var appleSignIn = appleSignIn

        NavigationStack {
            ZStack {
                MiniMatchColors.background
                    .ignoresSafeArea()

                switch model.screen {
                case .home:
                    HomeView(
                        model: model,
                        gameCenter: gameCenter,
                        appleSignIn: appleSignIn,
                        multiplayerIsUnavailable: !gameCenter.restrictionIsResolved
                            || gameCenter.isMultiplayerRestricted,
                        multiplayerIsRestricted: gameCenter.isMultiplayerRestricted
                    )
                case .lobby:
                    LobbyView(
                        model: model,
                        profileImage: gameCenter.avatarImage,
                        canShareInvites: !gameCenter.personalizedCommunicationIsRestricted
                    )
                case .result:
                    ResultView(model: model)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.screen == .lobby {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task {
                                await model.leaveTable()
                            }
                        } label: {
                            if model.isWorking {
                                ProgressView()
                            } else {
                                Label("Leave", systemImage: "chevron.backward")
                            }
                        }
                        .disabled(model.isWorking)
                    }
                    ToolbarItem(placement: .principal) {
                        BrandHeader(compact: true)
                    }
                }
                if gameCenter.isAuthenticated {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileMenu(
                            gameCenter: gameCenter,
                            appleSignIn: appleSignIn,
                            canManageAccount: model.screen == .home
                        )
                    }
                }
            }
        }
        .tint(MiniMatchColors.blueText)
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
        .task(id: model.completedMatchWin) {
            guard let win = model.completedMatchWin else { return }
            await gameCenter.reportMatchWin(win)
        }
        .task {
            await appleSignIn.refreshCredentialState()
            for await _ in NotificationCenter.default.notifications(
                named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
            ) {
                if model.screen != .home {
                    await model.leaveTable()
                    model.discardSession()
                }
                await appleSignIn.refreshCredentialState()
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
        .alert("Apple sign-in failed", isPresented: $appleSignIn.isShowingError) {
            Button("OK") {}
        } message: {
            Text(appleSignIn.errorMessage)
        }
        .alert("Delete your profile?", isPresented: $appleSignIn.isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                Task {
                    await appleSignIn.deleteProfile()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if appleSignIn.isSignedIn {
                Text("You’ll confirm with Apple before Mini Match removes your account and anonymizes your saved table profile. Game Center scores remain managed by Apple.")
            } else {
                Text("This removes your Mini Match account and anonymizes your saved table profile. Game Center scores remain managed by Apple.")
            }
        }
        .sheet(isPresented: $appleSignIn.isAwaitingDeletionAuthorization) {
            DeletionAuthorizationView(appleSignIn: appleSignIn)
        }
    }
}
