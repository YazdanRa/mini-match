import SwiftUI
import UIKit

struct LobbyView: View {
    let model: GameModel
    let playerImages: [String: UIImage]
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if let table = model.table {
                    VStack(spacing: 6) {
                        Text(table.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Round \(table.currentRound?.number ?? 1)")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(MiniMatchColors.ink)

                    PlayersSection(
                        table: table,
                        currentPlayerID: model.currentPlayerID,
                        playerImages: playerImages
                    )

                    if model.isReconnecting {
                        Label("Reconnecting to the table…", systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    PickSection(model: model)

                    if model.isHost {
                        HostActionSection(model: model)
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observeTable()
        }
        .onChange(of: model.table?.eventSequence) {
            guard let table = model.table else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: String(
                    localized: "Players: \(table.players.count). Locked in: \(table.players.filter(\.isLocked).count).",
                    comment: "VoiceOver lobby update; the first variable is the player count and the second is the locked-in player count."
                )
            )
        }
    }
}

#Preview {
    LobbyView(
        model: GameModel.preview(table: PreviewFixtures.lobbyTable),
        playerImages: [:]
    )
    .background(MiniMatchColors.background)
}
