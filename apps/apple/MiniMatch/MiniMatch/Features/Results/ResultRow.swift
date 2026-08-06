import SwiftUI

struct ResultRow: View {
    let row: ResultPresentation.Row

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                identity
                Spacer()
                pick
                status
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    identity
                    Spacer()
                    pick
                }
                status
            }
        }
        .padding(12)
        .background(row.status == .winner ? MiniMatchColors.blue.opacity(0.08) : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("result-row-\(row.playerID)")
        .accessibilityLabel(Text(accessibilityText))
    }

    private var identity: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 8) {
                Text(row.displayName)
                    .font(.headline)
                if let wins = row.wins {
                    Text(wins.formatted())
                        .font(.subheadline.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MiniMatchColors.blue.opacity(0.12), in: Capsule())
                }
            }
            Text("selected")
                .font(.subheadline)
                .foregroundStyle(MiniMatchColors.ink)
        }
    }

    private var pick: some View {
        Text(row.pick.formatted())
            .font(.title.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(row.status == .duplicate ? MiniMatchColors.coralText : MiniMatchColors.blueText)
    }

    private var status: some View {
        Label(
            statusText,
            systemImage: row.status == .duplicate ? "xmark.circle.fill" : "checkmark.circle.fill"
        )
        .font(.subheadline)
        .foregroundStyle(MiniMatchColors.ink)
    }

    private var statusText: LocalizedStringResource {
        switch row.status {
        case .winner:
            "Winner"
        case .duplicate:
            "Duplicate"
        case .unique:
            "Unique"
        }
    }

    private var accessibilityText: LocalizedStringResource {
        if let wins = row.wins {
            "\(row.displayName), win count \(wins), selected \(row.pick), \(statusText)"
        } else {
            "\(row.displayName), selected \(row.pick), \(statusText)"
        }
    }
}

#Preview {
    ResultRow(row: PreviewFixtures.winnerRow)
        .padding()
}
