import SwiftUI
import UIKit

struct LobbyView: View {
    let model: GameModel
    let profileImage: UIImage?
    let canShareInvites: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if let table = model.table {
                    VStack(spacing: 6) {
                        Text(table.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text("Round \(table.currentRound?.number ?? 1)")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(MiniMatchColors.ink)

                    PlayersSection(
                        table: table,
                        currentPlayerID: model.currentPlayerID,
                        profileImage: profileImage
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

                    InviteSection(table: table, canShare: canShareInvites)
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
                    localized: "\(table.players.count) players. \(table.players.filter(\.isLocked).count) locked in."
                )
            )
        }
    }
}

#Preview {
    LobbyView(
        model: GameModel.preview(table: PreviewFixtures.lobbyTable),
        profileImage: nil,
        canShareInvites: true
    )
    .background(MiniMatchColors.background)
}
