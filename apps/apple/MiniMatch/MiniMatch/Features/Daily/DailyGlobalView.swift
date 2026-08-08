import AuthenticationServices
import Foundation
import SwiftUI

struct DailyGlobalView: View {
    let model: DailyGlobalModel
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DailyHero()
                    .frame(maxWidth: 520)

                if model.requiresAuthentication
                    || !appleSignIn.isSignedIn
                    || !gameCenter.isAuthenticated
                {
                    DailyAuthenticationCard(
                        appleSignIn: appleSignIn,
                        gameCenterIsAuthenticated: gameCenter.isAuthenticated
                    )
                    .frame(maxWidth: 520)
                } else if let table = model.table {
                    if !model.errorMessage.isEmpty {
                        DailyRefreshError(
                            message: model.errorMessage,
                            retry: { Task { await model.refresh() } }
                        )
                        .frame(maxWidth: 520)
                    }

                    DailyRoundCards(model: model, table: table)
                    DailyWinsLink(
                        wins: table.localPlayerDailyWins,
                        gameCenter: gameCenter
                    )
                    .frame(maxWidth: 520)
                } else if model.isLoading || model.isRefreshing {
                    ProgressView("Loading today’s table…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .frame(maxWidth: 520)
                } else {
                    DailyLoadFailure(
                        message: model.errorMessage,
                        retry: { Task { await model.refresh() } }
                    )
                    .frame(maxWidth: 520)
                }
            }
            .frame(maxWidth: 920)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(MiniMatchColors.background)
        .navigationTitle("Daily Table")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refresh()
        }
        .task(id: "\(appleSignIn.isSignedIn):\(gameCenter.authenticatedTeamPlayerID ?? "")") {
            guard appleSignIn.isSignedIn, gameCenter.isAuthenticated else { return }
            await model.refresh()
        }
        .task(id: model.table?.currentRound.closesAt) {
            guard model.table != nil else { return }
            let remaining = model.timeRemaining(at: Date())
            guard remaining > 0 else {
                await model.refresh()
                return
            }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
        .task(id: model.table?.previousResult?.status) {
            await model.refreshUntilPreviousResultSettles()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
    }
}

private struct DailyRoundCards: View {
    let model: DailyGlobalModel
    let table: DailyGlobalTable

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                DailyPreviousResultCard(result: table.previousResult)
                    .frame(minWidth: 320, maxWidth: .infinity)
                DailyTodayCard(model: model, round: table.currentRound)
                    .frame(minWidth: 320, maxWidth: .infinity)
            }

            VStack(spacing: 20) {
                DailyPreviousResultCard(result: table.previousResult)
                DailyTodayCard(model: model, round: table.currentRound)
            }
            .frame(maxWidth: 520)
        }
    }
}

private struct DailyHero: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe.americas.fill")
                .font(.largeTitle.bold())
                .foregroundStyle(MiniMatchColors.coralBrand)
                .accessibilityHidden(true)

            Text("One world. One number.")
                .font(.title.bold())
                .foregroundStyle(MiniMatchColors.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Pick the lowest number chosen by only one player. Results are revealed after the daily table closes.")
                .font(.subheadline)
                .foregroundStyle(MiniMatchColors.ink)
                .multilineTextAlignment(.center)
        }
    }
}

private struct DailyAuthenticationCard: View {
    let appleSignIn: AppleSignInModel
    let gameCenterIsAuthenticated: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DailyCard(accent: MiniMatchColors.coralBrand) {
            VStack(spacing: 14) {
                Label("Sign in to play", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.title3.bold())
                    .foregroundStyle(MiniMatchColors.ink)

                Text("Daily Table requires an Apple-linked Mini Match account and Game Center.")
                    .font(.subheadline)
                    .foregroundStyle(MiniMatchColors.ink)
                    .multilineTextAlignment(.center)

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
                } else if !gameCenterIsAuthenticated {
                    Label("Sign in to Game Center in Settings to continue.", systemImage: "gamecontroller.fill")
                        .font(.subheadline)
                        .foregroundStyle(MiniMatchColors.ink)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DailyRefreshError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MiniMatchColors.coralText)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(MiniMatchColors.ink)
            Spacer(minLength: 0)
            Button("Retry", action: retry)
                .font(.footnote.bold())
        }
        .padding(14)
        .background(MiniMatchColors.coralBrand.opacity(0.1), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct DailyLoadFailure: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Daily Table is unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message.isEmpty ? String(localized: "Try again in a moment.") : message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(minHeight: 260)
    }
}

private struct DailyPreviousResultCard: View {
    let result: DailyGlobalResult?

    var body: some View {
        DailyCard(accent: MiniMatchColors.blueText) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Yesterday", systemImage: "clock.arrow.circlepath")
                    .font(.title2.bold())
                    .foregroundStyle(MiniMatchColors.ink)
                    .accessibilityAddTraits(.isHeader)

                if let result {
                    Text(formattedRoundDate(result.roundDate))
                        .font(.caption)
                        .foregroundStyle(MiniMatchColors.ink)
                    DailyPreviousResultContent(result: result)
                } else {
                    Text("No previous result is available yet.")
                        .foregroundStyle(MiniMatchColors.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("daily-previous-result")
    }

    private func formattedRoundDate(_ roundDate: String) -> String {
        let parts = roundDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return roundDate }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(
            calendar: calendar,
            timeZone: .gmt,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        )
        guard let date = components.date else { return roundDate }
        var format = Date.FormatStyle.dateTime.year().month(.wide).day()
        format.timeZone = .gmt
        return date.formatted(format)
    }
}

private struct DailyPreviousResultContent: View {
    let result: DailyGlobalResult

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch result.status {
            case .calculating:
                DailyResultLine(
                    title: "Calculating the result…",
                    systemImage: "hourglass",
                    color: MiniMatchColors.blueText
                )
            case .empty:
                DailyResultLine(
                    title: "No one entered yesterday.",
                    systemImage: "minus.circle.fill",
                    color: MiniMatchColors.blueText
                )
            case .insufficientPlayers:
                DailyResultLine(
                    title: "Not enough players entered.",
                    systemImage: "person.2.slash.fill",
                    color: MiniMatchColors.blueText
                )
            case .noUniquePick:
                DailyResultLine(
                    title: "No number was unique.",
                    systemImage: "equal.circle.fill",
                    color: MiniMatchColors.coralText
                )
            case .winner:
                if let winningPick = result.winningPick {
                    DailyResultLine(
                        title: "Winning number: \(winningPick)",
                        systemImage: "trophy.fill",
                        color: MiniMatchColors.coralText
                    )
                }
            }

            if result.status != .calculating {
                Text("Players: \(result.participantCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiniMatchColors.ink)
            }

            if let localPick = result.localPick {
                Divider()
                Text("Your number: \(localPick)")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.ink)
                if result.localPlayerWon {
                    Label("You won!", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(MiniMatchColors.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DailyResultLine: View {
    let title: LocalizedStringResource
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(.headline)
        .foregroundStyle(MiniMatchColors.ink)
    }
}

private struct DailyTodayCard: View {
    @Bindable var model: DailyGlobalModel
    let round: DailyGlobalRound
    @State private var isConfirmingPick = false

    var body: some View {
        DailyCard(accent: MiniMatchColors.coralBrand) {
            VStack(spacing: 14) {
                Label("Today", systemImage: "sun.max.fill")
                    .font(.title2.bold())
                    .foregroundStyle(MiniMatchColors.ink)
                    .accessibilityAddTraits(.isHeader)

                DailyDeadline(model: model, closesAt: round.closesAt)

                if let localPick = round.localPick {
                    DailySubmittedPick(pick: localPick)
                } else {
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
                        .disabled(model.isSubmitting)
                        .accessibilityLabel("Your daily number")

                    if !model.pickText.isEmpty && !model.canSubmit {
                        Label(
                            "Enter a positive whole number.",
                            systemImage: "exclamationmark.circle.fill"
                        )
                            .font(.footnote)
                            .foregroundStyle(MiniMatchColors.ink)
                    }

                    Button {
                        isConfirmingPick = true
                    } label: {
                        if model.isSubmitting {
                            ProgressView("Locking…")
                        } else {
                            Label("Lock my daily number", systemImage: "lock.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                    .disabled(model.isSubmitting || !model.canSubmit)
                    .accessibilityHint("Your number cannot be changed after it is locked")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Lock \(model.pickText) for today?",
            isPresented: $isConfirmingPick,
            titleVisibility: .visible
        ) {
            Button("Lock this number") {
                Task { await model.submitPick() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You cannot change this number after it is locked.")
        }
        .accessibilityIdentifier("daily-today-card")
    }
}

private struct DailyDeadline: View {
    let model: DailyGlobalModel
    let closesAt: Date

    var body: some View {
        VStack(spacing: 6) {
            Text("Rounds close at 00:00 UTC.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiniMatchColors.ink)
            Text("Local close: \(closesAt, format: .dateTime.hour().minute())")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiniMatchColors.ink)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Duration.seconds(model.timeRemaining(at: context.date))
                Label {
                    Text(remaining.formatted(.time(pattern: .hourMinuteSecond)))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "timer")
                }
                .font(.headline)
                .foregroundStyle(MiniMatchColors.ink)
                .accessibilityLabel("Time remaining: \(remaining.formatted(.time(pattern: .hourMinuteSecond)))")
            }
        }
    }
}

private struct DailySubmittedPick: View {
    let pick: UInt64

    var body: some View {
        VStack(spacing: 10) {
            Label("Locked for today", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(MiniMatchColors.ink)
            Text(pick, format: .number)
                .font(.largeTitle.bold().monospacedDigit())
                .foregroundStyle(MiniMatchColors.ink)
            Text("Private until the table closes.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiniMatchColors.ink)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Locked for today. Your number is \(pick). It stays private until the table closes.")
    }
}

private struct DailyWinsLink: View {
    let wins: UInt64
    let gameCenter: GameCenterModel

    var body: some View {
        NavigationLink {
            DailyLeaderboardView(gameCenter: gameCenter)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.title2.bold())
                    .foregroundStyle(MiniMatchColors.coralText)
                    .frame(width: 48, height: 48)
                    .background(MiniMatchColors.coralBrand.opacity(0.12), in: .rect(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Wins")
                        .font(.headline)
                        .foregroundStyle(MiniMatchColors.ink)
                    Text("Your wins: \(wins)")
                        .font(.subheadline)
                        .foregroundStyle(MiniMatchColors.ink)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .foregroundStyle(MiniMatchColors.blueText)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(MiniMatchColors.surface, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("daily-wins-link")
    }
}

private struct DailyLeaderboardView: View {
    let gameCenter: GameCenterModel

    var body: some View {
        Group {
            if gameCenter.isLoadingDailyLeaderboard
                && gameCenter.dailyLeaderboardEntries.isEmpty
            {
                ProgressView("Loading leaderboard…")
                    .controlSize(.large)
            } else if gameCenter.dailyLeaderboardEntries.isEmpty {
                DailyLeaderboardEmptyState(
                    message: gameCenter.dailyLeaderboardErrorMessage,
                    retry: { Task { await gameCenter.loadDailyLeaderboard() } }
                )
            } else {
                List {
                    if let local = gameCenter.dailyLocalLeaderboardEntry {
                        Section("Your rank") {
                            DailyLeaderboardRow(entry: local)
                        }
                    }

                    Section("Global top 100") {
                        ForEach(gameCenter.dailyLeaderboardEntries) { entry in
                            DailyLeaderboardRow(entry: entry)
                        }
                    }
                }
                .refreshable {
                    await gameCenter.loadDailyLeaderboard()
                }
            }
        }
        .navigationTitle("Daily Wins")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await gameCenter.loadDailyLeaderboard()
        }
    }
}

private struct DailyLeaderboardEmptyState: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Leaderboard unavailable", systemImage: "trophy")
        } description: {
            Text(message ?? String(localized: "The Daily Wins leaderboard is unavailable."))
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

private struct DailyLeaderboardRow: View {
    let entry: DailyLeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.rank, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(MiniMatchColors.ink)
                .frame(minWidth: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.ink)
                if entry.isLocalPlayer {
                    Text("You")
                        .font(.caption.bold())
                        .foregroundStyle(MiniMatchColors.ink)
                }
            }

            Spacer(minLength: 0)

            Text("Wins: \(entry.score)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(MiniMatchColors.ink)
        }
        .frame(minHeight: 44)
        .listRowBackground(
            entry.isLocalPlayer
                ? MiniMatchColors.blueText.opacity(0.1)
                : MiniMatchColors.surface
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.displayName), wins: \(entry.score)")
        .accessibilityIdentifier(entry.isLocalPlayer ? "daily-local-rank" : "")
    }
}

private struct DailyCard<Content: View>: View {
    let accent: Color
    let content: Content

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(MiniMatchColors.surface, in: .rect(cornerRadius: 22))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent)
                    .frame(width: 5)
                    .padding(.vertical, 16)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
    }
}

#Preview("Submitted winner") {
    NavigationStack {
        DailyGlobalView(
            model: DailyGlobalModel(
                client: PreviewGameClient(),
                identityProvider: {
                    GameCenterIdentityDTO(
                        teamPlayerId: "preview-player",
                        publicKeyUrl: "https://example.com/key",
                        signature: Data(),
                        salt: Data(),
                        timestamp: "0"
                    )
                }
            ),
            gameCenter: GameCenterModel.preview(),
            appleSignIn: AppleSignInModel()
        )
    }
}
