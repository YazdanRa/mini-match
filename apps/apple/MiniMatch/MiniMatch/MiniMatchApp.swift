import FirebaseCore
import SwiftUI

@main
struct MiniMatchApp: App {
    @State private var model = GameModel(client: GameClientFactory.make())
    @State private var loadedLaunchPreview = false

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
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
