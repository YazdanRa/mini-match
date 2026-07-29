import FirebaseCore
import SwiftUI

@main
struct MiniMatchApp: App {
    @State private var model = GameModel(client: GameClientFactory.make())
    @State private var gameCenter: GameCenterModel
    @State private var loadedLaunchPreview = false

    init() {
        FirebaseApp.configure()
        let arguments = ProcessInfo.processInfo.arguments
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _gameCenter = State(initialValue: GameCenterModel(
            isEnabled: !isTesting
                && !arguments.contains("--preview-lobby")
                && !arguments.contains("--preview-result")
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, gameCenter: gameCenter)
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
                        model.pickText = "2"
                        await model.lockPick()
                        await model.revealRound()
                    }
                    #endif
                }
        }
    }
}
