import SwiftUI
import UIKit

struct PlayersSection: View {
    let table: GameTable
    let currentPlayerID: String?
    let playerImages: [String: UIImage]
    let roundIsActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Players (\(table.players.count))")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if roundIsActive {
                    Text("\(table.players.filter(\.isLocked).count) locked")
                        .foregroundStyle(MiniMatchColors.blueText)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(table.players) { player in
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(player.id == currentPlayerID
                                          ? MiniMatchColors.blue
                                          : MiniMatchColors.coral.opacity(0.84))
                                    .frame(width: 62, height: 62)
                                    .overlay {
                                        if let image = playerImages[player.id] {
                                            ProfileAvatar(image: image, size: 56)
                                        } else {
                                            Text(player.avatarGlyph)
                                                .font(.title2.bold())
                                                .accessibilityHidden(true)
                                        }
                                    }

                                if roundIsActive {
                                    Image(systemName: player.isLocked ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(player.isLocked ? MiniMatchColors.blueText : .secondary)
                                        .background(Circle().fill(MiniMatchColors.background))
                                        .contentTransition(.symbolEffect(.replace))
                                        .animation(
                                            reduceMotion ? nil : .snappy(duration: 0.2),
                                            value: player.isLocked
                                        )
                                }
                            }

                            Text(player.displayName)
                                .font(.subheadline.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            if player.id == currentPlayerID {
                                Text("You")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(MiniMatchColors.blue, in: Capsule())
                            }

                            Text(player.id == table.hostPlayerID ? "Host" : player.isLocked ? "Locked" : "Joined")
                                .font(.caption)
                                .foregroundStyle(player.id == table.hostPlayerID ? MiniMatchColors.coralText : .secondary)
                        }
                        .frame(minWidth: 88)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: player))
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.25),
                    value: table.players.map(\.id)
                )
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(MiniMatchColors.ink)
    }

    private func accessibilityLabel(for player: GamePlayer) -> Text {
        var details = [String]()
        if player.id == currentPlayerID {
            details.append(String(localized: "You"))
        }
        if player.id == table.hostPlayerID {
            details.append(String(localized: "Host"))
        }
        if roundIsActive {
            details.append(
                player.isLocked ? String(localized: "Locked") : String(localized: "Not locked")
            )
        }
        if playerImages[player.id] != nil {
            return Text("\(player.displayName), Game Center profile photo, \(details.formatted())")
        }
        let avatar = PlayerAvatar(rawValue: player.avatarID)?.label ?? PlayerAvatar.spark.label
        return Text("\(player.displayName), \(avatar) avatar, \(details.formatted())")
    }
}

#Preview {
    PlayersSection(
        table: PreviewFixtures.lobbyTable,
        currentPlayerID: PreviewFixtures.currentPlayerID,
        playerImages: [:],
        roundIsActive: false
    )
    .padding()
}
