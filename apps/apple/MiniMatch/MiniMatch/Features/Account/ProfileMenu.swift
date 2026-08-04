import SwiftUI

struct ProfileMenu: View {
    let gameCenter: GameCenterModel
    let showSettings: () -> Void

    var body: some View {
        Menu {
            Text(gameCenter.displayName)
            Button("Settings", systemImage: "gearshape", action: showSettings)
                .accessibilityIdentifier("profile-settings-button")
        } label: {
            ProfileAvatar(image: gameCenter.avatarImage, size: 36)
        }
        .accessibilityLabel(
            gameCenter.displayName.isEmpty ? "Game Center profile" : "Profile for \(gameCenter.displayName)"
        )
        .accessibilityHint("Opens account and game options")
    }
}

#Preview {
    ProfileMenu(
        gameCenter: GameCenterModel.preview(),
        showSettings: {}
    )
}
