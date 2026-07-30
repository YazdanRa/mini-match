import SwiftUI

struct InviteSection: View {
    let table: GameTable
    let canShare: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Invite friends")
                .font(.headline)
                .foregroundStyle(MiniMatchColors.ink)

            HStack(spacing: 12) {
                Label(table.joinCode, systemImage: "qrcode")
                    .frame(maxWidth: .infinity)

                if canShare {
                    ShareLink(item: "Join \(table.name) with code \(table.joinCode)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                }
            }
            .font(.headline)
            .foregroundStyle(MiniMatchColors.blueText)
            .padding()
            .background(MiniMatchColors.surface)
            .clipShape(.rect(cornerRadius: 18))
        }
    }
}
