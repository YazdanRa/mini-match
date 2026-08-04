import Lottie
import SwiftUI

struct RoundResultSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let result: ResultPresentation

    var body: some View {
        VStack(spacing: 14) {
            if result.winnerName != nil {
                TrophyCelebration(animates: !reduceMotion)
            }

            WinnerCard(result: result)

            VStack(alignment: .leading, spacing: 12) {
                Text("This round")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.ink)
                    .accessibilityAddTraits(.isHeader)

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
        }
    }
}

private struct TrophyCelebration: View {
    let animates: Bool

    var body: some View {
        Group {
            if animates {
                LottieView {
                    try await DotLottieFile.named("trophy")
                } placeholder: {
                    staticTrophy
                }
                .resizable()
                .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                .aspectRatio(contentMode: .fit)
            } else {
                staticTrophy
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var staticTrophy: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: 88, weight: .semibold))
            .foregroundStyle(.yellow)
    }
}

#Preview("Winner") {
    RoundResultSection(result: PreviewFixtures.result)
        .padding()
        .background(MiniMatchColors.background)
}

#Preview("No winner") {
    RoundResultSection(result: PreviewFixtures.noWinnerResult)
        .padding()
        .background(MiniMatchColors.background)
}

#Preview("Static trophy") {
    TrophyCelebration(animates: false)
        .background(MiniMatchColors.background)
}
