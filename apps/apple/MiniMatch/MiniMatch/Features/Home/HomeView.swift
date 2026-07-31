import AuthenticationServices
import SwiftUI

struct HomeView: View {
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                BrandHeader()

                Spacer(minLength: 72)

                Text("Small game. Big fun.")
                    .font(.title3.bold())
                    .foregroundStyle(MiniMatchColors.ink)

                Text("Pick a non-negative whole number. Lowest number picked by only one player wins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HomeRoundPreview()
                    .padding(.top, 12)

                HomeStatusSection(
                    gameCenter: gameCenter,
                    appleSignIn: appleSignIn
                )
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .overlay { HomeNumberPlayground() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HomeActionSection(
                gameCenter: gameCenter,
                appleSignIn: appleSignIn
            )
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
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
    }
}

private struct HomeRoundPreview: View {
    var body: some View {
        HStack(spacing: 14) {
            HomePickCard(
                value: "2",
                color: MiniMatchColors.coralBrand,
                systemImage: "xmark",
                rotation: -7
            )
            HomePickCard(
                value: "2",
                color: MiniMatchColors.coralBrand,
                systemImage: "xmark",
                rotation: 5
            )
            HomePickCard(
                value: "5",
                color: MiniMatchColors.blueText,
                systemImage: "checkmark",
                rotation: -3
            )
            .offset(y: -10)
        }
        .accessibilityHidden(true)
    }
}

private struct HomePickCard: View {
    let value: String
    let color: Color
    let systemImage: String
    let rotation: Double

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(value)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 72, height: 82)
                .background(MiniMatchColors.surface, in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(color.opacity(0.22), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 5)

            Image(systemName: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color, in: .circle)
                .offset(x: 7, y: -7)
        }
        .rotationEffect(.degrees(rotation))
    }
}

private struct HomeActionSection: View {
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if appleSignIn.isSignedIn {
            Button {
                gameCenter.startMatchmaking()
            } label: {
                Label("Invite players", systemImage: "person.3.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.blue))
            .disabled(multiplayerIsUnavailable)
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
        }
    }

    private var multiplayerIsUnavailable: Bool {
        !gameCenter.restrictionIsResolved
            || gameCenter.isMultiplayerRestricted
            || !gameCenter.isAuthenticated
            || gameCenter.displayName.isEmpty
    }
}

private struct HomeStatusSection: View {
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel

    var body: some View {
        if appleSignIn.isSignedIn {
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
            Text("Sign in to secure this player account with your Apple account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct HomeNumberPlayground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HomeNumberToken(value: "1", color: MiniMatchColors.coralBrand, size: 84)
                    .position(x: 18, y: proxy.size.height * 0.16)
                    .offset(
                        x: isDrifting ? 8 : -8,
                        y: isDrifting ? -10 : 10
                    )

                HomeNumberToken(value: "2", color: MiniMatchColors.blueText, size: 68)
                    .position(x: proxy.size.width - 18, y: proxy.size.height * 0.28)
                    .offset(
                        x: isDrifting ? -10 : 10,
                        y: isDrifting ? 8 : -8
                    )

                HomeNumberToken(value: "2", color: MiniMatchColors.coralBrand, size: 58)
                    .position(x: 18, y: proxy.size.height * 0.54)
                    .offset(
                        x: isDrifting ? 6 : -6,
                        y: isDrifting ? 10 : -10
                    )

                HomeNumberToken(value: "3", color: MiniMatchColors.blueText, size: 92)
                    .position(x: proxy.size.width - 18, y: proxy.size.height * 0.68)
                    .offset(
                        x: isDrifting ? -7 : 7,
                        y: isDrifting ? -9 : 9
                    )

                HomeNumberToken(value: "4", color: MiniMatchColors.coralBrand, size: 72)
                    .position(x: 18, y: proxy.size.height * 0.80)
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
            .foregroundStyle(color.opacity(0.55))
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: .circle)
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
