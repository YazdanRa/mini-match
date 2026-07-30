import SwiftUI

struct ResultView: View {
    let model: GameModel
    @AccessibilityFocusState private var winnerIsFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            if let table = model.table, let result = model.result {
                VStack(spacing: 14) {
                    Text("Mini Match")
                        .font(.largeTitle.weight(.black))
                        .fontDesign(.rounded)
                        .foregroundStyle(MiniMatchColors.ink)

                    Text("Pick a number. Lowest unique number wins.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    WinnerCard(result: result)
                        .accessibilityFocused($winnerIsFocused)
                    ScoreSection(table: table)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("This round")
                            .font(.headline)
                            .foregroundStyle(MiniMatchColors.ink)

                        VStack(spacing: 0) {
                            ForEach(result.rows) { row in
                                ResultRow(row: row)
                                if row.id != result.rows.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(MiniMatchColors.surface)
                        .clipShape(.rect(cornerRadius: 20))
                    }

                    Button {
                        model.nextRound()
                    } label: {
                        Label(
                            table.state == .finished ? "Back to home" : "Next round",
                            systemImage: table.state == .finished ? "house.fill" : "chevron.right"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                }
                .padding(16)
                .task {
                    winnerIsFocused = true
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observeTable()
        }
    }
}

#Preview {
    ResultView(model: GameModel.preview(table: PreviewFixtures.resultTable))
        .background(MiniMatchColors.background)
}
