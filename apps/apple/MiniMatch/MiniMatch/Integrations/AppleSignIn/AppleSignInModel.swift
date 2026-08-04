import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppleSignInModel {
    private let client: any GameClient
    private var currentNonce: String?

    private(set) var isWorking = false
    private(set) var isSignedIn: Bool
    private(set) var canDeleteProfile: Bool
    private(set) var errorMessage = ""
    var isShowingError = false
    var isConfirmingDeletion = false
    var isAwaitingDeletionAuthorization = false

    init(client: any GameClient) {
        self.client = client
        isSignedIn = Self.currentUserUsesApple
        canDeleteProfile = Auth.auth().currentUser != nil
    }

    init(previewIsSignedIn: Bool = true) {
        client = PreviewGameClient()
        isSignedIn = previewIsSignedIn
        canDeleteProfile = previewIsSignedIn
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try Self.randomNonce()
            currentNonce = nonce
            request.nonce = Self.sha256(nonce)
        } catch {
            showError(error)
        }
    }

    func prepareDeletion(_ request: ASAuthorizationAppleIDRequest) {
        prepare(request)
    }

    func completeDeletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let identityToken = appleCredential.identityToken,
                  let idToken = String(data: identityToken, encoding: .utf8),
                  let authorizationCode = appleCredential.authorizationCode,
                  let code = String(data: authorizationCode, encoding: .utf8)
            else {
                showError(AppleSignInError.invalidCredential)
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: nil
            )
            currentNonce = nil
            Task {
                await deleteAccount(reauthenticatingWith: credential, authorizationCode: code)
            }

        case let .failure(error):
            currentNonce = nil
            let authorizationError = error as NSError
            guard authorizationError.domain != ASAuthorizationError.errorDomain
                    || authorizationError.code != ASAuthorizationError.canceled.rawValue
            else { return }
            showError(error)
        }
    }

    func requestDeletionAuthorization() {
        isAwaitingDeletionAuthorization = true
    }

    func requestProfileDeletionConfirmation() {
        isConfirmingDeletion = true
    }

    func cancelDeletionAuthorization() {
        isAwaitingDeletionAuthorization = false
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            isSignedIn = false
            canDeleteProfile = false
        } catch {
            showError(error)
        }
    }

    func deleteProfile() async {
        guard !Self.currentUserUsesApple else {
            requestDeletionAuthorization()
            return
        }
        guard let user = Auth.auth().currentUser else {
            canDeleteProfile = false
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await client.deleteProfile()
            try await user.delete()
            isSignedIn = false
            canDeleteProfile = false
        } catch {
            showError(error)
        }
    }

    func refreshProfileAvailability() {
        canDeleteProfile = isSignedIn || Auth.auth().currentUser != nil
    }

    func refreshCredentialState() async {
        guard !(client is PreviewGameClient) else { return }
        guard let user = Auth.auth().currentUser else {
            isSignedIn = false
            canDeleteProfile = false
            return
        }
        canDeleteProfile = true
        guard let appleUserID = user.providerData
                  .first(where: { $0.providerID == "apple.com" })?
                  .uid
        else {
            isSignedIn = false
            return
        }
        let firebaseUserID = user.uid

        do {
            let state = try await credentialState(for: appleUserID)
            guard Auth.auth().currentUser?.uid == firebaseUserID else { return }
            guard state == .authorized else {
                try? Auth.auth().signOut()
                isSignedIn = false
                canDeleteProfile = false
                return
            }
            isSignedIn = true
        } catch {
            guard Auth.auth().currentUser?.uid == firebaseUserID else { return }
            showError(error)
        }
    }

    func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let identityToken = appleCredential.identityToken,
                  let idToken = String(data: identityToken, encoding: .utf8)
            else {
                showError(AppleSignInError.invalidCredential)
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )
            currentNonce = nil
            Task {
                await authenticate(with: credential)
            }

        case let .failure(error):
            currentNonce = nil
            let authorizationError = error as NSError
            guard authorizationError.domain != ASAuthorizationError.errorDomain
                    || authorizationError.code != ASAuthorizationError.canceled.rawValue
            else { return }
            showError(error)
        }
    }

    nonisolated static func randomNonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AppleSignInError.randomnessUnavailable
        }
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    nonisolated static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static var currentUserUsesApple: Bool {
        Auth.auth().currentUser?.providerData.contains { $0.providerID == "apple.com" } == true
    }

    private func authenticate(with credential: AuthCredential) async {
        isWorking = true
        defer { isWorking = false }

        do {
            if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
                _ = try await currentUser.link(with: credential)
            } else {
                _ = try await Auth.auth().signIn(with: credential)
            }
            isSignedIn = true
            canDeleteProfile = true
        } catch {
            let authError = error as NSError
            if authError.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
               let updatedCredential = authError.userInfo[AuthErrorUserInfoUpdatedCredentialKey]
                    as? AuthCredential
            {
                do {
                    _ = try await Auth.auth().signIn(with: updatedCredential)
                    isSignedIn = true
                    canDeleteProfile = true
                    return
                } catch {
                    showError(error)
                    return
                }
            }
            showError(error)
        }
    }

    private func deleteAccount(
        reauthenticatingWith credential: AuthCredential,
        authorizationCode: String
    ) async {
        guard let user = Auth.auth().currentUser else {
            isAwaitingDeletionAuthorization = false
            isSignedIn = false
            canDeleteProfile = false
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await user.reauthenticate(with: credential)
            try await client.deleteProfile()
            try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
            try await user.delete()
            isAwaitingDeletionAuthorization = false
            isSignedIn = false
            canDeleteProfile = false
        } catch {
            showError(error)
        }
    }

    private func credentialState(
        for userID: String
    ) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) {
                state,
                error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}

private enum AppleSignInError: LocalizedError {
    case invalidCredential
    case randomnessUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            String(localized: "Apple did not return a usable sign-in credential.")
        case .randomnessUnavailable:
            String(localized: "A secure sign-in request could not be created.")
        }
    }
}
