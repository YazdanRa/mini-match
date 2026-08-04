import SwiftUI

struct HostActionSection: View {
    let model: GameModel

    var body: some View {
        let isWaiting = model.table?.currentRound == nil
        let isEnabled = isWaiting ? model.canStartRound : model.canReveal
        let accessibilityHint: LocalizedStringResource = isWaiting
            ? "Available to the host when at least two players are in the lobby"
            : "Available only to the host after every player locks a number"

        Button {
            Task {
                if isWaiting {
                    await model.startRound()
                } else {
                    await model.revealRound()
                }
            }
        } label: {
            if model.isWorking {
                if isWaiting {
                    ProgressView("Starting…")
                } else {
                    ProgressView("Revealing…")
                }
            } else if isWaiting {
                if model.canStartRound {
                    Label("Start round", systemImage: "play.fill")
                } else {
                    Label("Waiting for another player", systemImage: "person.badge.clock")
                }
            } else {
                Label(
                    model.canReveal ? "Reveal round" : "Everyone must lock first",
                    systemImage: model.canReveal ? "sparkles" : "lock.fill"
                )
            }
        }
        .buttonStyle(PrimaryButtonStyle(
            color: isEnabled ? MiniMatchColors.coral : Color.secondary.opacity(0.35)
        ))
        .disabled(
            !isEnabled || model.isWorking || model.multiplayerIsRestricted
        )
        .accessibilityHint(accessibilityHint)
    }
}

#Preview {
    HostActionSection(model: GameModel.preview(table: PreviewFixtures.readyTable))
        .padding()
}
