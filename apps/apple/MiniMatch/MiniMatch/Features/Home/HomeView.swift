import AuthenticationServices
import SwiftUI

struct HomeView: View {
    let model: GameModel
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    let multiplayerIsUnavailable: Bool
    let multiplayerIsRestricted: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var entryMode: TableEntrySheet.Mode?

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
