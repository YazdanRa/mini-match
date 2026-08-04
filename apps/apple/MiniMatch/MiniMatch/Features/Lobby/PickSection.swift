import SwiftUI

struct PickSection: View {
    @Bindable var model: GameModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Enter your number")
                .font(.title2.bold())
                .foregroundStyle(MiniMatchColors.ink)
                .accessibilityAddTraits(.isHeader)

            Text("Lowest number picked by only one player wins.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("1", text: $model.pickText)
                .font(.largeTitle.bold().monospacedDigit())
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .padding(.vertical, 12)
                .background(MiniMatchColors.surface)
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(MiniMatchColors.blueText, lineWidth: 3)
                }
                .disabled(model.currentPlayerIsLocked || model.multiplayerIsRestricted)
                .accessibilityLabel("Your number")

            if !model.pickText.isEmpty && !model.canLockPick {
                Text("Enter a positive whole number.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if model.currentPlayerIsLocked {
                Label("You’re locked in!", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.blueText)
                Text("Your number stays private until reveal.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        await model.lockPick()
                    }
                } label: {
                    if model.isWorking {
                        ProgressView("Locking…")
                            .tint(.white)
                    } else {
                        Label("Lock my number", systemImage: "lock.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                .disabled(
                    model.isWorking
                        || model.multiplayerIsRestricted
                        || !model.canLockPick
                )
            }
        }
    }
}

#Preview {
    PickSection(model: GameModel.preview(table: PreviewFixtures.lobbyTable))
        .padding()
}
