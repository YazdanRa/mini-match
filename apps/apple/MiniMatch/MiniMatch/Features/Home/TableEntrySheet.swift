import SwiftUI

struct TableEntrySheet: View {
    enum Mode: String, Identifiable {
        case create
        case join

        var id: Self { self }
    }

    private enum FocusedField {
        case entry
        case displayName
    }

    let mode: Mode
    let model: GameModel
    let gameCenter: GameCenterModel
    let multiplayerIsRestricted: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var tableName = ""
    @State private var tableCode = ""
    @State private var displayName = ""
    @State private var avatarID = PlayerAvatar.allCases.randomElement()!.rawValue
    @State private var errorMessage: String?
    @AccessibilityFocusState private var errorIsFocused: Bool
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode == .create ? "Table name" : "Table code")
                            .font(.headline)

                        if mode == .create {
                            TextField(
                                "Table name",
                                text: $tableName,
                                prompt: Text("Friday game")
                            )
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .entry)
                                .submitLabel(usesGameCenterProfile ? .go : .next)
                                .onSubmit { submitEntryField() }
                        } else {
                            TextField(
                                "Table code",
                                text: $tableCode,
                                prompt: Text("6-character code")
                            )
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .entry)
                                .submitLabel(usesGameCenterProfile ? .go : .next)
                                .onSubmit { submitEntryField() }
                        }
                    }

                    if usesGameCenterProfile {
                        Text(
                            resolvedDisplayName.isEmpty
                                ? "Loading Game Center profile…"
                                : "Playing as \(resolvedDisplayName)"
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your name")
                                .font(.headline)
                            TextField("Your name", text: $displayName, prompt: Text("Name"))
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .focused($focusedField, equals: .displayName)
                                .submitLabel(.go)
                                .onSubmit { submitIfPossible() }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(MiniMatchColors.coralText)
                            .accessibilityFocused($errorIsFocused)
                    }

                    Button {
                        submit()
                    } label: {
                        Group {
                            if model.isWorking {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(mode == .create ? "Creating…" : "Joining…")
                                }
                            } else {
                                Text(mode == .create ? "Create table" : "Join table")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 22)
                    }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit || model.isWorking || multiplayerIsRestricted)
                }
                .padding(24)
            }
            .navigationTitle(mode == .create ? "Create a table" : "Join a table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(model.isWorking)
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        .presentationDetents([.height(usesGameCenterProfile ? 320 : 380), .large])
        .presentationDragIndicator(.visible)
    }

    private var usesGameCenterProfile: Bool {
        gameCenter.isAuthenticated
    }

    private var resolvedDisplayName: String {
        let name = usesGameCenterProfile ? gameCenter.displayName : displayName
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        let entry = mode == .create ? tableName : tableCode
        return !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !resolvedDisplayName.isEmpty
    }

    private func submitEntryField() {
        if usesGameCenterProfile {
            submitIfPossible()
        } else {
            focusedField = .displayName
        }
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        submit()
    }

    private func submit() {
        focusedField = nil
        Task {
            do {
                let identity = try await gameCenter.identityVerification()
                let succeeded = if mode == .create {
                    await model.createTable(
                        name: tableName,
                        displayName: resolvedDisplayName,
                        avatarID: avatarID,
                        gameCenterIdentity: identity
                    )
                } else {
                    await model.joinTable(
                        code: tableCode,
                        displayName: resolvedDisplayName,
                        avatarID: avatarID,
                        gameCenterIdentity: identity
                    )
                }
                if succeeded {
                    dismiss()
                } else {
                    errorMessage = model.errorMessage
                    model.isShowingError = false
                    errorIsFocused = true
                }
            } catch {
                errorMessage = error.localizedDescription
                errorIsFocused = true
            }
        }
    }
}

#Preview {
    TableEntrySheet(
        mode: .create,
        model: GameModel.preview(),
        gameCenter: GameCenterModel.preview(isAuthenticated: false),
        multiplayerIsRestricted: false
    )
}
