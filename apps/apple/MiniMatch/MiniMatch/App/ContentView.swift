import AuthenticationServices
import SwiftUI

struct ContentView: View {
    let model: GameModel
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingLeave = false
    @State private var isShowingSettings = false

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
                        gameCenter: gameCenter,
                        appleSignIn: appleSignIn
                    )
                case .lobby:
                    LobbyView(
                        model: model,
                        playerImages: gameCenter.playerImages
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.screen == .lobby {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isConfirmingLeave = true
                        } label: {
                            if model.isWorking {
                                ProgressView()
                                    .accessibilityLabel("Leaving table")
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
                    if model.screen == .lobby {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                gameCenter.showActivity()
                            } label: {
                                Label("Invite", systemImage: "person.badge.plus")
                            }
                            .disabled(!gameCenter.canShareActivity)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileMenu(
                            gameCenter: gameCenter,
                            showSettings: {
                                appleSignIn.refreshProfileAvailability()
                                isShowingSettings = true
                            }
                        )
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(
                    appleSignIn: appleSignIn,
                    canManageAccount: model.screen == .home
                )
            }
        }
        .tint(MiniMatchColors.blueText)
        .confirmationDialog(
            "Leave this match?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Leave match", role: .destructive) {
                Task {
                    await model.leaveTable()
                    if model.screen == .home {
                        gameCenter.endMatch()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll leave the table for the other players.")
        }
        .onChange(
            of: gameCenter.isAuthenticated
                && model.screen == .home
                && gameCenter.authentication?.id == nil
                && gameCenter.matchmaking?.id == nil,
            initial: true
        ) { _, shouldActivateAccessPoint in
            gameCenter.setAccessPointActive(shouldActivateAccessPoint)
        }
        .onChange(
            of: gameCenter.restrictionIsResolved
                && !gameCenter.isMultiplayerRestricted
                && gameCenter.isAuthenticated,
            initial: true
        ) { _, canRestoreSession in
            Task {
                await model.setMultiplayerRestricted(!canRestoreSession)
                if canRestoreSession {
                    let teamPlayerID = gameCenter.authenticatedTeamPlayerID
                    await model.restoreSession(
                        gameCenterPlayerID: teamPlayerID,
                        identityIsCurrent: {
                            gameCenter.isAuthenticated
                                && gameCenter.authenticatedTeamPlayerID == teamPlayerID
                        }
                    )
                } else {
                    gameCenter.endMatch()
                }
            }
        }
        .onChange(of: gameCenter.authenticatedTeamPlayerID) { _, playerID in
            if model.handleGameCenterPlayerChange(to: playerID) {
                gameCenter.endMatch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                gameCenter.refreshRestrictions()
                Task {
                    guard gameCenter.restrictionIsResolved,
                          !gameCenter.isMultiplayerRestricted,
                          gameCenter.isAuthenticated
                    else { return }
                    let teamPlayerID = gameCenter.authenticatedTeamPlayerID
                    await model.restoreSession(
                        gameCenterPlayerID: teamPlayerID,
                        identityIsCurrent: {
                            gameCenter.isAuthenticated
                                && gameCenter.authenticatedTeamPlayerID == teamPlayerID
                        }
                    )
                }
            }
        }
        .onChange(of: model.screen) { _, screen in
            if screen == .home {
                gameCenter.endMatch()
            }
        }
        .task {
            gameCenter.attach(to: model)
            await appleSignIn.refreshCredentialState()
            for await _ in NotificationCenter.default.notifications(
                named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
            ) {
                if model.screen != .home {
                    await model.leaveTable()
                    model.discardSession()
                    gameCenter.endMatch()
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
        .fullScreenCover(item: $gameCenter.matchmaking, onDismiss: {
            gameCenter.dismissMatchmaking()
        }) { matchmaking in
            GameCenterAuthenticationView(viewController: matchmaking.viewController)
                .ignoresSafeArea()
        }
        .alert(
            "Couldn’t continue",
            isPresented: $model.isShowingError,
            actions: { Button("OK") {} },
            message: { Text(model.errorMessage) }
        )
        .alert("Game Center failed", isPresented: $gameCenter.isShowingError) {
            Button("OK") {}
        } message: {
            Text(gameCenter.errorMessage)
        }
        .alert("Apple sign-in failed", isPresented: $appleSignIn.isShowingError) {
            Button("OK") {}
        } message: {
            Text(appleSignIn.errorMessage)
        }
        .alert("Delete your profile?", isPresented: $appleSignIn.isConfirmingDeletion) {
            Button("Delete profile permanently", role: .destructive) {
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

#Preview {
    ContentView(
        model: GameModel.preview(),
        gameCenter: GameCenterModel.preview(),
        appleSignIn: AppleSignInModel()
    )
}
