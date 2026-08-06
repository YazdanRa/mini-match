import SwiftUI

struct JoinCodeSheet: View {
    let gameCenter: GameCenterModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCodeFocused: Bool
    @State private var partyCode = ""
    private let soundEffectPlayer = SoundEffectPlayer.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "number")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(MiniMatchColors.blue, in: .rect(cornerRadius: 20))
                        .rotationEffect(.degrees(-5))
                        .shadow(color: MiniMatchColors.blue.opacity(0.25), radius: 10, y: 6)
                        .accessibilityHidden(true)

                    Text("Enter the party code from Game Center.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("Party code", text: $partyCode)
                        .font(.title3.monospaced().weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .focused($isCodeFocused)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(MiniMatchColors.surface, in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isCodeFocused
                                        ? MiniMatchColors.blueText
                                        : Color.secondary.opacity(0.35),
                                    lineWidth: isCodeFocused ? 3 : 1
                                )
                        }
                        .onSubmit(join)

                    Button(action: join) {
                        Label("Join", systemImage: "arrow.forward")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                    .disabled(
                        partyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MiniMatchColors.background)
            .navigationTitle("Join with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        soundEffectPlayer.play(.mainButton)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { isCodeFocused = true }
    }

    private func join() {
        guard !partyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        soundEffectPlayer.play(.mainButton)
        dismiss()
        gameCenter.joinActivity(code: partyCode)
    }
}

#Preview {
    JoinCodeSheet(gameCenter: GameCenterModel.preview())
}
