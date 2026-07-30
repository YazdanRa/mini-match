import SwiftUI

struct ScoreSection: View {
    let table: GameTable

    var body: some View {
        VStack(spacing: 12) {
            Text("Score")
                .font(.headline)
                .foregroundStyle(MiniMatchColors.ink)

            ScrollView(.horizontal) {
                HStack(spacing: 22) {
                    ForEach(table.players) { player in
                        VStack(spacing: 2) {
                            Text(player.displayName)
                                .font(.headline)
                            Text(player.wins.formatted())
                                .font(.title.bold())
                                .foregroundStyle(
                                    player.id == table.winnerPlayerID ? MiniMatchColors.coralText : MiniMatchColors.blueText
                                )
                            if player.id == table.winnerPlayerID {
                                Label("Game winner", systemImage: "trophy.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(MiniMatchColors.coralText)
                            }
                        }
                        .frame(minWidth: 68)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(player.displayName), \(player.wins) wins\(player.id == table.winnerPlayerID ? ", game winner" : "")"
                        )
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            Text("First to \(table.winsToFinish) wins")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .background(MiniMatchColors.surface)
        .clipShape(.rect(cornerRadius: 20))
    }
}
