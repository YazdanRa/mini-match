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

                Spacer(minLength: 52)

                Text("Small game. Big fun.")
                    .font(.title3.bold())
                    .foregroundStyle(MiniMatchColors.ink)

                Text("Pick a non-negative whole number. Lowest number picked by only one player wins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if appleSignIn.isSignedIn {
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
                } else {
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
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [
                    MiniMatchColors.coralBrand.opacity(0.06),
                    .clear,
                    MiniMatchColors.blueText.opacity(0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .overlay { HomeNumberPlayground() }
    }

    private var multiplayerIsUnavailable: Bool {
        !gameCenter.restrictionIsResolved
            || gameCenter.isMultiplayerRestricted
            || !gameCenter.isAuthenticated
            || gameCenter.displayName.isEmpty
    }
}

private struct HomeNumberPlayground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HomeNumberToken(value: "1", color: MiniMatchColors.coralBrand, size: 84)
                    .position(x: 0, y: proxy.size.height * 0.16)
                    .offset(
                        x: isDrifting ? 8 : -8,
                        y: isDrifting ? -10 : 10
                    )

                HomeNumberToken(value: "2", color: MiniMatchColors.blueText, size: 68)
                    .position(x: proxy.size.width, y: proxy.size.height * 0.28)
                    .offset(
                        x: isDrifting ? -10 : 10,
                        y: isDrifting ? 8 : -8
                    )

                HomeNumberToken(value: "2", color: MiniMatchColors.coralBrand, size: 58)
                    .position(x: 0, y: proxy.size.height * 0.54)
                    .offset(
                        x: isDrifting ? 6 : -6,
                        y: isDrifting ? 10 : -10
                    )

                HomeNumberToken(value: "3", color: MiniMatchColors.blueText, size: 92)
                    .position(x: proxy.size.width, y: proxy.size.height * 0.68)
                    .offset(
                        x: isDrifting ? -7 : 7,
                        y: isDrifting ? -9 : 9
                    )

                HomeNumberToken(value: "4", color: MiniMatchColors.coralBrand, size: 72)
                    .position(x: 0, y: proxy.size.height * 0.88)
                    .offset(
                        x: isDrifting ? 9 : -9,
                        y: isDrifting ? -6 : 6
                    )
            }
            .onAppear {
                isDrifting = !reduceMotion
            }
            .onChange(of: reduceMotion) { _, newValue in
                isDrifting = !newValue
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 4.5).repeatForever(autoreverses: true),
                value: isDrifting
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct HomeNumberToken: View {
    let value: String
    let color: Color
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounceTrigger = 0

    var body: some View {
        Text(value)
            .font(.system(size: size * 0.48, weight: .black, design: .rounded))
            .foregroundStyle(color.opacity(0.3))
            .frame(width: size, height: size)
            .background(color.opacity(0.1), in: .circle)
            .phaseAnimator(
                [false, true, false],
                trigger: bounceTrigger
            ) { content, isBouncing in
                content
                    .scaleEffect(!reduceMotion && isBouncing ? 1.12 : 1)
                    .rotationEffect(.degrees(!reduceMotion && isBouncing ? 6 : 0))
            } animation: { isBouncing in
                isBouncing ? .bouncy(duration: 0.18) : .snappy(duration: 0.28)
            }
            .contentShape(.circle)
            .onTapGesture {
                guard !reduceMotion else { return }
                bounceTrigger += 1
            }
    }
}

#Preview("Signed in") {
    HomeView(
        gameCenter: GameCenterModel.preview(),
        appleSignIn: AppleSignInModel()
    )
}

#Preview("Signed out") {
    HomeView(
        gameCenter: GameCenterModel.preview(),
        appleSignIn: AppleSignInModel(previewIsSignedIn: false)
    )
}
