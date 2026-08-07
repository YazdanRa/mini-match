import FirebaseAppCheck
import FirebaseCore
import SwiftUI

@main
struct MiniMatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GameModel
    @State private var dailyGlobal: DailyGlobalModel
    @State private var gameCenter: GameCenterModel
    @State private var appleSignIn: AppleSignInModel
    @State private var preferences: UserPreferences
    @State private var loadedLaunchPreview = false

    init() {
        _preferences = State(initialValue: ProcessInfo.processInfo.isMiniMatchPreviewLaunch
            ? .preview()
            : UserPreferences())
        #if targetEnvironment(simulator)
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        FirebaseApp.configure()
        let client = GameClientFactory.make()
        let arguments = ProcessInfo.processInfo.arguments
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #if DEBUG
        if arguments.contains("--preview-settings")
            || arguments.contains("--preview-signed-out")
            || arguments.contains("--preview-lobby")
            || arguments.contains("--preview-result")
            || arguments.contains("--preview-daily")
        {
            let gameCenter = GameCenterModel.preview()
            _model = State(initialValue: GameModel.preview())
            _appleSignIn = State(initialValue: AppleSignInModel(
                previewIsSignedIn: !arguments.contains("--preview-signed-out")
            ))
            _gameCenter = State(initialValue: gameCenter)
            _dailyGlobal = State(initialValue: DailyGlobalModel(
                client: client,
                identityProvider: {
                    GameCenterIdentityDTO(
                        teamPlayerId: "preview-player",
                        publicKeyUrl: "https://example.com/key",
                        signature: Data(),
                        salt: Data(),
                        timestamp: "0"
                    )
                }
            ))
            return
        }
        #endif
        let gameCenter = GameCenterModel(
            isEnabled: !isTesting
                && !arguments.contains("--preview-lobby")
                && !arguments.contains("--preview-result")
        )
        _model = State(initialValue: GameModel(client: client))
        _appleSignIn = State(initialValue: AppleSignInModel(client: client))
        _gameCenter = State(initialValue: gameCenter)
        _dailyGlobal = State(initialValue: DailyGlobalModel(
            client: client,
            identityProvider: {
                try await gameCenter.requiredIdentityVerification()
            },
            winsReporter: { total, identity in
                gameCenter.reportDailyWins(total, verifiedBy: identity)
            }
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                model: model,
                dailyGlobal: dailyGlobal,
                gameCenter: gameCenter,
                appleSignIn: appleSignIn,
                preferences: preferences,
                showDailyOnLaunch: ProcessInfo.processInfo.arguments.contains("--preview-daily")
            )
                .task {
                    gameCenter.authenticate()
                    #if DEBUG
                    guard !loadedLaunchPreview else { return }
                    loadedLaunchPreview = true
                    let arguments = ProcessInfo.processInfo.arguments
                    guard arguments.contains("--preview-lobby")
                            || arguments.contains("--preview-result")
                    else { return }

                    _ = await model.createTable(name: "Friday Mini Match", displayName: "Maya")
                    if arguments.contains("--preview-result") {
                        await model.startRound()
                        model.pickText = "2"
                        await model.lockPick()
                        await model.revealRound()
                    }
                    #endif
                }
                .task {
                    guard !ProcessInfo.processInfo.isMiniMatchPreviewLaunch else { return }
                    preferences.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active,
                          !ProcessInfo.processInfo.isMiniMatchPreviewLaunch
                    else { return }
                    preferences.synchronize()
                    Task {
                        await DailyChallengeReminder.reconcile(
                            isEnabled: preferences.dailyReminderEnabled
                        )
                    }
                }
        }
    }
}
