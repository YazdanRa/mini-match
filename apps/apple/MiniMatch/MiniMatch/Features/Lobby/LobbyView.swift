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
                        if let round = table.currentRound {
                            Text("Round \(round.number)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Lobby")
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text("Party code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(table.joinCode)
                                .font(.headline.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.top, 8)
                    }
                    .foregroundStyle(MiniMatchColors.ink)

                    PlayersSection(
                        table: table,
                        currentPlayerID: model.currentPlayerID,
                        playerImages: playerImages,
                        roundIsActive: table.currentRound != nil
                    )

                    if model.isReconnecting {
                        Label("Reconnecting to the table…", systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if table.currentRound != nil {
                        PickSection(model: model)
                    } else if let result = model.result {
                        RoundResultSection(result: result)
                    }

                    if model.isHost {
                        HostActionSection(model: model)
                    } else if table.currentRound == nil {
                        Label("Waiting for the host to start a round", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
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
            guard let table = model.table, table.currentRound != nil else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: String(
                    localized: "Players: \(table.players.count). Locked in: \(table.players.filter(\.isLocked).count).",
                    comment: "VoiceOver lobby update; the first variable is the player count and the second is the locked-in player count."
                )
            )
        }
        .onChange(of: model.table?.lastResult?.roundNumber) {
            guard let result = model.result else { return }
            UIAccessibility.post(notification: .announcement, argument: result.accessibilitySummary)
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
