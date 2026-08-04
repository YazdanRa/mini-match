import SwiftUI

struct RoundResultSection: View {
    let result: ResultPresentation

    var body: some View {
        VStack(spacing: 14) {
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

#Preview {
    RoundResultSection(result: PreviewFixtures.result)
        .padding()
        .background(MiniMatchColors.background)
}
