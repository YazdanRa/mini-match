import AuthenticationServices
import SwiftUI
import UIKit

enum MiniMatchColors {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let navy = Color(red: 0.0, green: 0.15, blue: 0.36)
    static let blue = Color(red: 0.04, green: 0.29, blue: 0.76)
    static let blueText = Color(uiColor: .systemBlue)
    static let coral = Color(red: 0.71, green: 0.18, blue: 0.16)
    static let coralBrand = Color(uiColor: .systemRed)
    static let coralText = Color(uiColor: .systemRed)
}

private struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.78 : 1))
            .clipShape(.rect(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct BrandHeader: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? -6 : -10) {
            Text("Mini")
                .foregroundStyle(MiniMatchColors.coralBrand)
            Text("Match")
                .foregroundStyle(MiniMatchColors.blueText)
        }
        .font(compact ? .title : .largeTitle)
        .fontWeight(.black)
        .fontDesign(.rounded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mini Match")
    }
}

struct ProfileMenu: View {
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    let canManageAccount: Bool

    var body: some View {
        Menu {
            Text(gameCenter.displayName)
            Button("Leaderboard", systemImage: "trophy.fill") {
                gameCenter.showLeaderboard()
            }
            Button("Game Center profile", systemImage: "person.crop.circle") {
                gameCenter.showProfile()
            }
            Button("Settings", systemImage: "gearshape") {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button("Log out of Mini Match", systemImage: "rectangle.portrait.and.arrow.right") {
                appleSignIn.signOut()
            }
            .disabled(!canManageAccount)
            Button("Delete profile", systemImage: "trash", role: .destructive) {
                appleSignIn.isConfirmingDeletion = true
            }
            .disabled(!canManageAccount)
            if !canManageAccount {
                Text("Return home to manage this profile.")
            }
        } label: {
            ProfileAvatar(image: gameCenter.avatarImage, size: 36)
        }
        .accessibilityLabel(
            gameCenter.displayName.isEmpty ? "Game Center profile" : "Profile for \(gameCenter.displayName)"
        )
        .accessibilityHint("Opens account and game options")
    }
}

struct DeletionAuthorizationView: View {
    let appleSignIn: AppleSignInModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Confirm with Apple to revoke access and delete your Mini Match account.")
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(
                    .continue,
                    onRequest: appleSignIn.prepareDeletion,
                    onCompletion: appleSignIn.completeDeletion
                )
                .signInWithAppleButtonStyle(colorScheme == .dark ? .whiteOutline : .black)
                .frame(height: 52)
                .clipShape(.rect(cornerRadius: 14))
                .disabled(appleSignIn.isWorking)
            }
            .padding(28)
            .navigationTitle("Delete profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appleSignIn.cancelDeletionAuthorization()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ProfileAvatar: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct HomeView: View {
    let model: GameModel
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    let multiplayerIsUnavailable: Bool
    let multiplayerIsRestricted: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var entryMode: EntryMode?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                BrandHeader()

                Text("Small game. Big fun.")
                    .font(.title3.bold())
                    .foregroundStyle(MiniMatchColors.ink)

                Text("Pick a non-negative whole number. Lowest number picked by only one player wins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    entryMode = .create
                } label: {
                    Label("Create a table", systemImage: "person.3.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                .disabled(multiplayerIsUnavailable)

                Button {
                    entryMode = .join
                } label: {
                    Label("Join a table", systemImage: "person.2.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.coral))
                .disabled(multiplayerIsUnavailable)

                if multiplayerIsRestricted {
                    Label(
                        "Multiplayer is unavailable because of Screen Time settings.",
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                } else if multiplayerIsUnavailable {
                    ProgressView("Checking Game Center…")
                }

                if !appleSignIn.isSignedIn {
                    SignInWithAppleButton(
                        .continue,
                        onRequest: appleSignIn.prepare,
                        onCompletion: appleSignIn.complete
                    )
                    .signInWithAppleButtonStyle(
                        colorScheme == .dark ? .whiteOutline : .black
                    )
                    .frame(height: 52)
                    .clipShape(.rect(cornerRadius: 14))
                    .disabled(appleSignIn.isWorking)

                    Text("Sign in to secure this player account with your Apple account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $entryMode) { mode in
            TableEntrySheet(
                mode: mode,
                model: model,
                gameCenter: gameCenter,
                multiplayerIsRestricted: multiplayerIsRestricted
            )
        }
    }
}

private enum EntryMode: String, Identifiable {
    case create
    case join

    var id: Self { self }
}

private struct TableEntrySheet: View {
    private enum FocusedField {
        case entry
        case displayName
    }

    let mode: EntryMode
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

struct LobbyView: View {
    let model: GameModel
    let profileImage: UIImage?
    let canShareInvites: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if let table = model.table {
                    VStack(spacing: 6) {
                        Text(table.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text("Round \(table.currentRound?.number ?? 1)")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(MiniMatchColors.ink)

                    PlayersSection(
                        table: table,
                        currentPlayerID: model.currentPlayerID,
                        profileImage: profileImage
                    )

                    if model.isReconnecting {
                        Label("Reconnecting to the table…", systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    PickSection(model: model)

                    if model.isHost {
                        HostActionSection(model: model)
                    }

                    InviteSection(table: table, canShare: canShareInvites)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observeTable()
        }
        .onChange(of: model.table?.eventSequence) {
            guard let table = model.table else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(table.players.count) players. \(table.players.filter(\.isLocked).count) locked in."
            )
        }
    }
}

private struct PlayersSection: View {
    let table: GameTable
    let currentPlayerID: String?
    let profileImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Players (\(table.players.count))")
                    .font(.headline)
                Spacer()
                Text("\(table.players.filter(\.isLocked).count) locked")
                    .foregroundStyle(MiniMatchColors.blueText)
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
                                        if player.id == currentPlayerID, let profileImage {
                                            ProfileAvatar(image: profileImage, size: 56)
                                        } else {
                                            Text(player.avatarGlyph)
                                                .font(.title2.bold())
                                                .accessibilityHidden(true)
                                        }
                                    }

                                Image(systemName: player.isLocked ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                                    .foregroundStyle(player.isLocked ? MiniMatchColors.blueText : .secondary)
                                    .background(Circle().fill(MiniMatchColors.background))
                            }

                            Text(player.displayName)
                                .font(.subheadline.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            if player.id == currentPlayerID {
                                Text("You")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(MiniMatchColors.blue, in: Capsule())
                            }

                            Text(player.id == table.hostPlayerID ? "Host" : player.isLocked ? "Locked" : "Joined")
                                .font(.caption)
                                .foregroundStyle(player.id == table.hostPlayerID ? MiniMatchColors.coralText : .secondary)
                        }
                        .frame(width: 88)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(player.displayName), \(PlayerAvatar(rawValue: player.avatarID)?.label ?? "Spark") avatar, \(player.id == currentPlayerID ? "you, " : "")\(player.id == table.hostPlayerID ? "host, " : "")\(player.isLocked ? "locked" : "not locked")"
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(MiniMatchColors.ink)
    }

}

private struct PickSection: View {
    @Bindable var model: GameModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Enter your number")
                .font(.title2.bold())
                .foregroundStyle(MiniMatchColors.ink)

            Text("Lowest number picked by only one player wins.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("0", text: $model.pickText)
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
                .disabled(model.isWorking || model.multiplayerIsRestricted)
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

private struct InviteSection: View {
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

struct ResultView: View {
    let model: GameModel
    @AccessibilityFocusState private var winnerIsFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            if let table = model.table, let result = model.result {
                VStack(spacing: 14) {
                    Text("Mini Match")
                        .font(.largeTitle.weight(.black))
                        .fontDesign(.rounded)
                        .foregroundStyle(MiniMatchColors.ink)

                    Text("Pick a number. Lowest unique number wins.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    WinnerCard(result: result)
                        .accessibilityFocused($winnerIsFocused)
                    ScoreSection(table: table)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("This round")
                            .font(.headline)
                            .foregroundStyle(MiniMatchColors.ink)

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
                .task {
                    winnerIsFocused = true
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observeTable()
        }
    }
}

private struct WinnerCard: View {
    let result: ResultPresentation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: result.winnerName == nil ? "equal.circle.fill" : "trophy.fill")
                .font(.largeTitle)
                .foregroundStyle(result.winnerName == nil ? .white : Color.yellow)
                .accessibilityHidden(true)

            Text(result.winnerName.map { "\($0) wins!" } ?? "No winner")
                .font(.largeTitle.weight(.black))
                .fontDesign(.rounded)

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isHeader)
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

    private var accessibilitySummary: String {
        if let winnerName = result.winnerName, let winningPick = result.winningPick {
            return "\(winnerName) wins with \(winningPick)"
        }
        return "No winner. Every number was duplicated."
    }
}

private struct ScoreSection: View {
    let table: GameTable

    var body: some View {
        VStack(spacing: 12) {
            Text("Score")
                .font(.headline)
                .foregroundStyle(MiniMatchColors.ink)

            ScrollView(.horizontal) {
                HStack(spacing: 22) {
                    ForEach(table.players) { player in
                        VStack(spacing: 2) {
                            Text(player.displayName)
                                .font(.headline)
                            Text(player.wins.formatted())
                                .font(.title.bold())
                                .foregroundStyle(
                                    player.id == table.winnerPlayerID ? MiniMatchColors.coralText : MiniMatchColors.blueText
                                )
                            if player.id == table.winnerPlayerID {
                                Label("Game winner", systemImage: "trophy.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(MiniMatchColors.coralText)
                            }
                        }
                        .frame(minWidth: 68)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(player.displayName), \(player.wins) wins\(player.id == table.winnerPlayerID ? ", game winner" : "")"
                        )
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.displayName), selected \(row.pick), \(statusText)")
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
            .foregroundStyle(row.status == .duplicate ? MiniMatchColors.coralText : MiniMatchColors.blueText)
    }

    private var status: some View {
        Label(
            statusText,
            systemImage: row.status == .duplicate ? "xmark.circle.fill" : "checkmark.circle.fill"
        )
        .font(.subheadline)
        .foregroundStyle(row.status == .duplicate ? MiniMatchColors.coralText : MiniMatchColors.blueText)
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
