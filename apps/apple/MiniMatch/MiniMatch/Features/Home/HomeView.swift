import AuthenticationServices
import SwiftUI

struct HomeView: View {
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    @Environment(\.colorScheme) private var colorScheme

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
                    gameCenter.startMatchmaking()
                } label: {
                    Label("Invite players", systemImage: "person.3.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
                .disabled(multiplayerIsUnavailable)

                if gameCenter.isMultiplayerRestricted {
                    Label(
                        "Multiplayer is unavailable because of Screen Time settings.",
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                } else if !gameCenter.restrictionIsResolved {
                    ProgressView("Checking Game Center…")
                } else if !gameCenter.isAuthenticated {
                    Label(
                        "Sign in to Game Center to play with friends.",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                } else if gameCenter.displayName.isEmpty {
                    ProgressView("Loading Game Center profile…")
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
    }

    private var multiplayerIsUnavailable: Bool {
        !gameCenter.restrictionIsResolved
            || gameCenter.isMultiplayerRestricted
            || !gameCenter.isAuthenticated
            || gameCenter.displayName.isEmpty
    }
}

#Preview {
    HomeView(
        gameCenter: GameCenterModel.preview(),
        appleSignIn: AppleSignInModel()
    )
}
