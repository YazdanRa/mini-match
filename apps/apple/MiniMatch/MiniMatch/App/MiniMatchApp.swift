import FirebaseCore
import SwiftUI

@main
struct MiniMatchApp: App {
    @State private var model: GameModel
    @State private var gameCenter: GameCenterModel
    @State private var appleSignIn: AppleSignInModel
    @State private var loadedLaunchPreview = false

    init() {
        FirebaseApp.configure()
        let client = GameClientFactory.make()
        let arguments = ProcessInfo.processInfo.arguments
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _model = State(initialValue: GameModel(client: client))
        _appleSignIn = State(initialValue: AppleSignInModel(client: client))
        _gameCenter = State(initialValue: GameCenterModel(
            isEnabled: !isTesting
                && !arguments.contains("--preview-lobby")
                && !arguments.contains("--preview-result")
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, gameCenter: gameCenter, appleSignIn: appleSignIn)
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
        }
    }
}
