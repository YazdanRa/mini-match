import SwiftUI
import UIKit

struct SettingsView: View {
    let appleSignIn: AppleSignInModel
    let canManageAccount: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsHeader()
                LanguageSettingsCard()

                if appleSignIn.isSignedIn {
                    AccountSettingsCard(
                        appleSignIn: appleSignIn,
                        canManageAccount: canManageAccount
                    )
                }

                if appleSignIn.canDeleteProfile {
                    DeleteProfileCard(
                        appleSignIn: appleSignIn,
                        canManageAccount: canManageAccount
                    )
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(MiniMatchColors.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings-page")
    }
}

private struct SettingsHeader: View {
    var body: some View {
        VStack(spacing: 8) {
            BrandHeader(compact: true)
            Text("Game settings")
                .font(.title2.bold())
                .fontDesign(.rounded)
                .foregroundStyle(MiniMatchColors.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Make Mini Match feel right for you.")
                .font(.subheadline)
                .foregroundStyle(MiniMatchColors.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }
}

private struct LanguageSettingsCard: View {
    private static let languageSettingsURL = URL(string: UIApplication.openSettingsURLString)!

    var body: some View {
        Link(destination: Self.languageSettingsURL) {
            SettingsCard(accent: MiniMatchColors.blueText) {
                LanguageSettingsLabel(languageName: languageName)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Language")
        .accessibilityValue(languageName)
        .accessibilityHint("Opens Mini Match Settings, where you can change the language")
        .accessibilityIdentifier("language-settings-link")
    }

    private var languageName: String {
        let identifier = Bundle.main.preferredLocalizations.first ?? "en"
        let languageLocale = Locale(identifier: identifier)
        return languageLocale.localizedString(forLanguageCode: identifier) ?? identifier
    }
}

private struct LanguageSettingsLabel: View {
    let languageName: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsIcon(systemName: "globe", color: MiniMatchColors.blueText)
                    Spacer(minLength: 8)
                    LanguageChevron()
                }
                LanguageSettingsCopy(languageName: languageName)
            }
        } else {
            HStack(spacing: 16) {
                SettingsIcon(systemName: "globe", color: MiniMatchColors.blueText)
                LanguageSettingsCopy(languageName: languageName)
                Spacer(minLength: 8)
                LanguageChevron()
            }
        }
    }
}

private struct LanguageSettingsCopy: View {
    let languageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Language")
                .font(.headline)
                .foregroundStyle(MiniMatchColors.ink)
            Text(languageName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MiniMatchColors.ink)
            Text("Change in iOS Settings")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MiniMatchColors.ink)
        }
    }
}

private struct LanguageChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.subheadline.bold())
            .foregroundStyle(.tertiary)
    }
}

private struct AccountSettingsCard: View {
    let appleSignIn: AppleSignInModel
    let canManageAccount: Bool

    var body: some View {
        SettingsCard(accent: MiniMatchColors.blue) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Player account", systemImage: "person.crop.circle.fill")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.ink)
                    .accessibilityAddTraits(.isHeader)

                Button("Log out of Mini Match", systemImage: "rectangle.portrait.and.arrow.right") {
                    appleSignIn.signOut()
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(MiniMatchColors.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(MiniMatchColors.blueText, lineWidth: 2)
                }
                .disabled(!canManageAccount || appleSignIn.isWorking)

                if !canManageAccount {
                    Text("Return home to manage this profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DeleteProfileCard: View {
    let appleSignIn: AppleSignInModel
    let canManageAccount: Bool

    var body: some View {
        SettingsCard(accent: MiniMatchColors.coralBrand) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Danger zone", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("Permanently deletes your Mini Match account. This cannot be undone.")
                    .font(.headline)
                    .foregroundStyle(MiniMatchColors.ink)

                Button(role: .destructive) {
                    appleSignIn.requestProfileDeletionConfirmation()
                } label: {
                    Label("Delete profile", systemImage: "trash.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: MiniMatchColors.coral))
                .disabled(!canManageAccount || appleSignIn.isWorking)
                .accessibilityHint("Requires confirmation. This cannot be undone.")
                .accessibilityIdentifier("delete-profile-button")

                if !canManageAccount {
                    Text("Return home to manage this profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsIcon: View {
    let systemName: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size = 48.0

    var body: some View {
        Image(systemName: systemName)
            .font(.title2.bold())
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 15))
    }
}

private struct SettingsCard<Content: View>: View {
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

#Preview {
    NavigationStack {
        SettingsView(
            appleSignIn: AppleSignInModel(),
            canManageAccount: true
        )
    }
}
