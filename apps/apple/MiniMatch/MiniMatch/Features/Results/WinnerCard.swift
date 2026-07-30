import SwiftUI

struct WinnerCard: View {
    let result: ResultPresentation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: result.winnerName == nil ? "equal.circle.fill" : "trophy.fill")
                .font(.largeTitle)
                .foregroundStyle(result.winnerName == nil ? .white : Color.yellow)
                .accessibilityHidden(true)

            Text(result.winnerName.map { "\($0) wins!" } ?? "No winner")
                .font(.largeTitle.weight(.black))
                .fontDesign(.rounded)

            if let winningPick = result.winningPick {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Winning number")
                        pick(winningPick)
                    }
                    VStack {
                        Text("Winning number")
                        pick(winningPick)
                    }
                }
            } else {
                Text("Every number was duplicated.")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(MiniMatchColors.blue)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isHeader)
    }

    private var accessibilitySummary: String {
        if let winnerName = result.winnerName, let winningPick = result.winningPick {
            return String(localized: "\(winnerName) wins with \(winningPick)")
        }
        return String(localized: "No winner. Every number was duplicated.")
    }

    private func pick(_ value: UInt64) -> some View {
        Text(value.formatted())
            .font(.title.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.white.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    WinnerCard(result: PreviewFixtures.result)
        .padding()
}
