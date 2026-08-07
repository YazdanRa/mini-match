import AuthenticationServices
import SwiftUI

struct ContentView: View {
    let model: GameModel
    let dailyGlobal: DailyGlobalModel
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    let preferences: UserPreferences
    let showDailyOnLaunch: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingLeave = false
    @State private var isShowingSettings = false
    @State private var isShowingDaily = false
    @State private var isJoiningWithCode = false
    private let soundEffectPlayer = SoundEffectPlayer.shared

    var body: some View {
        @Bindable var model = model
        @Bindable var gameCenter = gameCenter
        @Bindable var appleSignIn = appleSignIn

        NavigationStack {
            ZStack {
                MiniMatchColors.background
                    .ignoresSafeArea()

                if gameCenter.isPreparingLobby {
                    LobbyLoadingView(
                        model: model,
                        cancel: gameCenter.endMatch
                    )
                } else {
                    switch model.screen {
                    case .home:
                        HomeView(
                            gameCenter: gameCenter,
                            appleSignIn: appleSignIn,
                            isJoiningWithCode: $isJoiningWithCode,
                            openDailyTable: {
                                soundEffectPlayer.play(.mainButton)
                                isShowingDaily = true
                            }
                        )
                    case .lobby:
                        LobbyView(
                            model: model,
                            playerImages: gameCenter.playerImages
                        )
                    }
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
                    if !gameCenter.isPreparingLobby {
                        ToolbarItem(placement: .principal) {
                            BrandHeader(compact: true)
                        }
                    }
                }
                if gameCenter.isAuthenticated && !gameCenter.isPreparingLobby {
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
                                soundEffectPlayer.play(.mainButton)
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
                    preferences: preferences,
                    canManageAccount: model.screen == .home
                )
            }
            .navigationDestination(isPresented: $isShowingDaily) {
                DailyGlobalView(
                    model: dailyGlobal,
                    gameCenter: gameCenter,
                    appleSignIn: appleSignIn
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
                && !isShowingSettings
                && !isShowingDaily
                && !isJoiningWithCode
                && gameCenter.authentication?.id == nil
                && gameCenter.matchmaking?.id == nil
                && !gameCenter.isPreparingLobby,
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
            dailyGlobal.resetForAuthenticationChange()
            if model.handleGameCenterPlayerChange(to: playerID) {
                gameCenter.endMatch()
            }
        }
        .onChange(of: appleSignIn.isSignedIn) {
            dailyGlobal.resetForAuthenticationChange()
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
        .onChange(of: preferences.dailyReminderEnabled, initial: true) { _, isEnabled in
            guard !ProcessInfo.processInfo.isMiniMatchPreviewLaunch else { return }
            Task {
                await DailyChallengeReminder.reconcile(isEnabled: isEnabled)
            }
        }
        .task {
            gameCenter.attach(to: model)
            await appleSignIn.refreshCredentialState()
            if showDailyOnLaunch {
                isShowingDaily = true
            }
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

private struct LobbyLoadingView: View {
    let model: GameModel
    let cancel: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BrandHeader()

                Spacer(minLength: 72)

                Text("Lobby")
                    .font(.title.bold())
                    .foregroundStyle(MiniMatchColors.ink)
                    .accessibilityAddTraits(.isHeader)

                ProgressView("Starting…")
                    .controlSize(.large)
                    .foregroundStyle(MiniMatchColors.ink)

                if model.screen == .home {
                    Button("Cancel", role: .cancel, action: cancel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observeTable()
        }
    }
}

#Preview {
    ContentView(
        model: GameModel.preview(),
        dailyGlobal: DailyGlobalModel(
            client: PreviewGameClient(),
            identityProvider: {
                GameCenterIdentityDTO(
                    teamPlayerId: "preview-player",
                    publicKeyUrl: "https://example.com/key",
                    signature: Data(),
                    salt: Data(),
                    timestamp: "0"
                )
            }
        ),
        gameCenter: GameCenterModel.preview(),
        appleSignIn: AppleSignInModel(),
        preferences: .preview(),
        showDailyOnLaunch: false
    )
}

#Preview("Lobby loading") {
    LobbyLoadingView(model: GameModel.preview(), cancel: {})
        .background(MiniMatchColors.background)
}
