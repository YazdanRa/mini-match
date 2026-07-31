import SwiftUI
import UIKit

struct ProfileMenu: View {
    let gameCenter: GameCenterModel
    let appleSignIn: AppleSignInModel
    let canManageAccount: Bool

    var body: some View {
        Menu {
            Text(gameCenter.displayName)
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

#Preview {
    ProfileMenu(
        gameCenter: GameCenterModel.preview(),
        appleSignIn: AppleSignInModel(),
        canManageAccount: true
    )
}
