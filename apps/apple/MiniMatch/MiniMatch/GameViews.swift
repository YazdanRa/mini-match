import AuthenticationServices
import SwiftUI

enum MiniMatchColors {
    static let background = Color(red: 0.99, green: 0.97, blue: 0.92)
    static let surface = Color.white.opacity(0.78)
    static let navy = Color(red: 0.0, green: 0.15, blue: 0.36)
    static let blue = Color(red: 0.04, green: 0.29, blue: 0.76)
    static let coral = Color(red: 0.97, green: 0.31, blue: 0.27)
    static let coralText = Color(red: 0.68, green: 0.16, blue: 0.13)
}

private struct PrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(.rect(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BrandHeader: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? -6 : -10) {
            Text("Mini")
                .foregroundStyle(MiniMatchColors.coral)
            Text("Match")
                .foregroundStyle(MiniMatchColors.blue)
        }
        .font(.system(size: compact ? 38 : 58, weight: .black, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mini Match")
    }
}

struct HomeView: View {
    let model: GameModel
    @State private var entryMode: EntryMode?
    @State private var appleSignIn = AppleSignInModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BrandHeader()

            Text("Small game. Big fun.")
                .font(.title3.bold())
                .foregroundStyle(MiniMatchColors.navy)
                .padding(.top, 22)

            Spacer()

            VStack(spacing: 18) {
                Button {
                    entryMode = .create
                } label: {
                    Label("Create a table", systemImage: "person.3.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))

                Button {
                    entryMode = .join
                } label: {
                    Label("Join a table", systemImage: "person.2.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.coral))

                if appleSignIn.isSignedIn {
                    VStack(spacing: 10) {
                        Label("Signed in with Apple", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(MiniMatchColors.navy)
                            .accessibilityLabel("Signed in with Apple")

                        if appleSignIn.isAwaitingDeletionAuthorization {
                            Text("Confirm with Apple to revoke access and delete your account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            SignInWithAppleButton(
                                .continue,
                                onRequest: appleSignIn.prepareDeletion,
                                onCompletion: appleSignIn.completeDeletion
                            )
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 52)
                            .clipShape(.rect(cornerRadius: 14))

                            Button("Cancel deletion", role: .cancel) {
                                appleSignIn.cancelDeletionAuthorization()
                            }
                        } else {
                            Button("Delete account", role: .destructive) {
                                appleSignIn.isConfirmingDeletion = true
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    SignInWithAppleButton(
                        .continue,
                        onRequest: appleSignIn.prepare,
                        onCompletion: appleSignIn.complete
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(.rect(cornerRadius: 14))
                    .disabled(appleSignIn.isWorking)

                    Text("Sign in to keep this player identity with your Apple account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .sheet(item: $entryMode) { mode in
            TableEntrySheet(mode: mode, model: model)
        }
        .alert("Apple sign-in failed", isPresented: $appleSignIn.isShowingError) {
            Button("OK") {}
        } message: {
            Text(appleSignIn.errorMessage)
        }
        .alert("Delete your account?", isPresented: $appleSignIn.isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                appleSignIn.requestDeletionAuthorization()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll confirm with Apple before Mini Match revokes access and deletes the Firebase account.")
        }
        .task {
            await appleSignIn.refreshCredentialState()
            for await _ in NotificationCenter.default.notifications(
                named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
            ) {
                await appleSignIn.refreshCredentialState()
            }
        }
    }
}

private enum EntryMode: String, Identifiable {
    case create
    case join

    var id: Self { self }
}

private struct TableEntrySheet: View {
    let mode: EntryMode
    let model: GameModel

    @Environment(\.dismiss) private var dismiss
    @State private var tableName = "Friday Mini Match"
    @State private var tableCode = ""
    @State private var displayName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if mode == .create {
                    TextField("Table name", text: $tableName)
                        .textContentType(.organizationName)
                } else {
                    TextField("Table code", text: $tableCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                TextField("Your name", text: $displayName)
                    .textContentType(.name)
                    .submitLabel(.go)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(MiniMatchColors.coralText)
                }

                Button(mode == .create ? "Create table" : "Join table") {
                    Task {
                        let succeeded = if mode == .create {
                            await model.createTable(name: tableName, displayName: displayName)
                        } else {
                            await model.joinTable(code: tableCode, displayName: displayName)
                        }
                        if succeeded {
                            dismiss()
                        } else {
                            errorMessage = model.errorMessage
                            model.isShowingError = false
                        }
                    }
                }
                .disabled(model.isWorking)
            }
            .scrollContentBackground(.hidden)
            .background(MiniMatchColors.background)
            .navigationTitle(mode == .create ? "Create a table" : "Join a table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(MiniMatchColors.background)
    }
}

struct LobbyView: View {
    let model: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack {
                    Button("Leave", systemImage: "chevron.left") {
                        model.leaveTable()
                    }
                    Spacer()
                    BrandHeader(compact: true)
                    Spacer()
                    Color.clear.frame(width: 58)
                }

                if let table = model.table {
                    VStack(spacing: 6) {
                        Text(table.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text("Round \(table.currentRound?.number ?? 1)")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(MiniMatchColors.navy)

                    PlayersSection(table: table, currentPlayerID: model.currentPlayerID)
                    PickSection(model: model)

                    if model.isHost {
                        HostActionSection(model: model)
                    }

                    InviteSection(table: table)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct PlayersSection: View {
    let table: GameTable
    let currentPlayerID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Players (\(table.players.count))")
                    .font(.headline)
                Spacer()
                Text("\(table.players.filter(\.isLocked).count) locked")
                    .foregroundStyle(MiniMatchColors.blue)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(table.players) { player in
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(player.id == currentPlayerID
                                          ? MiniMatchColors.blue
                                          : MiniMatchColors.coral.opacity(0.84))
                                    .frame(width: 62, height: 62)
                                    .overlay {
                                        Text(initials(for: player.displayName))
                                            .font(.title2.bold())
                                            .foregroundStyle(.white)
                                    }

                                Image(systemName: player.isLocked ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                                    .foregroundStyle(player.isLocked ? MiniMatchColors.blue : .secondary)
                                    .background(Circle().fill(MiniMatchColors.background))
                            }

                            Text(player.displayName)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(player.id == table.hostPlayerID ? "Host" : player.isLocked ? "Locked" : "Joined")
                                .font(.caption)
                                .foregroundStyle(player.id == table.hostPlayerID ? MiniMatchColors.coralText : .secondary)
                        }
                        .frame(width: 74)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(player.displayName), \(player.id == table.hostPlayerID ? "host, " : "")\(player.isLocked ? "locked" : "not locked")"
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(MiniMatchColors.navy)
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct PickSection: View {
    @Bindable var model: GameModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Enter your number")
                .font(.title2.bold())
                .foregroundStyle(MiniMatchColors.navy)

            TextField("0", text: $model.pickText)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .padding(.vertical, 12)
                .background(MiniMatchColors.surface)
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(MiniMatchColors.blue, lineWidth: 3)
                }
                .disabled(model.currentPlayerIsLocked)
                .accessibilityLabel("Your number")

            if model.currentPlayerIsLocked {
                Label("You’re locked in!", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.blue)
                Text("Your number stays private until reveal.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        await model.lockPick()
                    }
                } label: {
                    Label("Lock my number", systemImage: "lock.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                .disabled(model.isWorking)
            }
        }
    }
}

private struct HostActionSection: View {
    let model: GameModel

    var body: some View {
        Button {
            Task {
                await model.revealRound()
            }
        } label: {
            Label(
                model.canReveal ? "Reveal round" : "Everyone must lock first",
                systemImage: model.canReveal ? "sparkles" : "lock.fill"
            )
        }
        .buttonStyle(PrimaryButtonStyle(
            color: model.canReveal ? MiniMatchColors.coral : Color.secondary.opacity(0.35)
        ))
        .disabled(!model.canReveal || model.isWorking)
        .accessibilityHint("Available only to the host after every player locks a number")
    }
}

private struct InviteSection: View {
    let table: GameTable

    var body: some View {
        VStack(spacing: 16) {
            Text("Invite friends")
                .font(.headline)
                .foregroundStyle(MiniMatchColors.navy)

            HStack(spacing: 12) {
                Label(table.joinCode, systemImage: "qrcode")
                    .frame(maxWidth: .infinity)

                ShareLink(item: "Join \(table.name) with code \(table.joinCode)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.headline)
            .foregroundStyle(MiniMatchColors.blue)
            .padding()
            .background(MiniMatchColors.surface)
            .clipShape(.rect(cornerRadius: 18))
        }
    }
}

struct ResultView: View {
    let model: GameModel

    var body: some View {
        ScrollView {
            if let table = model.table, let result = model.result {
                VStack(spacing: 14) {
                    Text("Mini Match")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(MiniMatchColors.navy)

                    Text("Pick a number. Lowest unique number wins.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    WinnerCard(result: result)
                    ScoreSection(table: table)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("This round")
                            .font(.headline)
                            .foregroundStyle(MiniMatchColors.navy)

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

                    Button {
                        model.nextRound()
                    } label: {
                        Label(
                            table.state == .finished ? "Back to home" : "Next round",
                            systemImage: table.state == .finished ? "house.fill" : "chevron.right"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                }
                .padding(16)
            }
        }
    }
}

private struct WinnerCard: View {
    let result: ResultPresentation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: result.winnerName == nil ? "equal.circle.fill" : "trophy.fill")
                .font(.system(size: 44))
                .foregroundStyle(result.winnerName == nil ? .white : Color.yellow)
                .accessibilityHidden(true)

            Text(result.winnerName.map { "\($0) wins!" } ?? "No winner")
                .font(.system(size: 36, weight: .black, design: .rounded))

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
        .accessibilityElement(children: .combine)
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

private struct ScoreSection: View {
    let table: GameTable

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 22) {
                    ForEach(table.players) { player in
                        VStack(spacing: 2) {
                            Text(player.displayName)
                                .font(.headline)
                            Text(player.wins.formatted())
                                .font(.title.bold())
                                .foregroundStyle(
                                    player.id == table.winnerPlayerID ? MiniMatchColors.coral : MiniMatchColors.blue
                                )
                        }
                        .frame(minWidth: 68)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            Text("First to \(table.winsToFinish) wins")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .background(MiniMatchColors.surface)
        .clipShape(.rect(cornerRadius: 20))
    }
}

private struct ResultRow: View {
    let row: ResultPresentation.Row

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                identity
                Spacer()
                pick
                status
                    .frame(width: 116, alignment: .leading)
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
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        VStack(alignment: .leading) {
            Text(row.displayName)
                .font(.headline)
            Text("selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var pick: some View {
        Text(row.pick.formatted())
            .font(.title.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(row.status == .duplicate ? MiniMatchColors.coral : MiniMatchColors.blue)
    }

    private var status: some View {
        Label(
            statusText,
            systemImage: row.status == .duplicate ? "xmark.circle.fill" : "checkmark.circle.fill"
        )
        .font(.subheadline)
        .foregroundStyle(row.status == .duplicate ? MiniMatchColors.coralText : MiniMatchColors.blue)
    }

    private var statusText: String {
        switch row.status {
        case .winner:
            "Lowest unique — winner"
        case .duplicate:
            "Duplicate — not unique"
        case .unique:
            "Unique"
        }
    }
}
