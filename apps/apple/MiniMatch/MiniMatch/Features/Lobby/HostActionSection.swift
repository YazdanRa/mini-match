import SwiftUI

struct HostActionSection: View {
    let model: GameModel

    var body: some View {
        Button {
            Task {
                await model.revealRound()
            }
        } label: {
            if model.isWorking {
                ProgressView("Revealing…")
                    .tint(.white)
            } else {
                Label(
                    model.canReveal ? "Reveal round" : "Everyone must lock first",
                    systemImage: model.canReveal ? "sparkles" : "lock.fill"
                )
            }
        }
        .buttonStyle(PrimaryButtonStyle(
            color: model.canReveal ? MiniMatchColors.coral : Color.secondary.opacity(0.35)
        ))
        .disabled(!model.canReveal || model.isWorking || model.multiplayerIsRestricted)
        .accessibilityHint("Available only to the host after every player locks a number")
    }
}

#Preview {
    HostActionSection(model: GameModel.preview(table: PreviewFixtures.readyTable))
        .padding()
}
