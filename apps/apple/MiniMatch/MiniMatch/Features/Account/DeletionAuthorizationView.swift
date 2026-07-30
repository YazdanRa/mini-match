import AuthenticationServices
import SwiftUI

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
