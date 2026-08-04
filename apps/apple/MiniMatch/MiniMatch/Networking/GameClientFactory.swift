import Foundation

enum GameClientFactory {
    static func make() -> any GameClient {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-lobby") || arguments.contains("--preview-result") {
            return PreviewGameClient()
        }
        return ConnectGameClient(
            baseURL: URL(
                string: "https://mini-match-api-704518244082.northamerica-northeast2.run.app"
            )!
        )
    }
}
