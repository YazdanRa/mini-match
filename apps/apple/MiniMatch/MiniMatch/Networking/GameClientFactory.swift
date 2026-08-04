import Foundation

enum GameClientFactory {
    static func make() -> any GameClient {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-settings")
            || arguments.contains("--preview-signed-out")
            || arguments.contains("--preview-lobby")
            || arguments.contains("--preview-result")
        {
            return PreviewGameClient()
        }
        #endif
        return ConnectGameClient(
            baseURL: URL(
                string: "https://mini-match-api-704518244082.northamerica-northeast2.run.app"
            )!
        )
    }
}
