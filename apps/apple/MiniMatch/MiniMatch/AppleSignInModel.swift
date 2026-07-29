import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppleSignInModel {
    private var currentNonce: String?

    private(set) var isWorking = false
    private(set) var isSignedIn: Bool
    private(set) var errorMessage = ""
    var isShowingError = false
    var isConfirmingDeletion = false
    var isAwaitingDeletionAuthorization = false

    init() {
        isSignedIn = Self.currentUserUsesApple
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

    func cancelDeletionAuthorization() {
        isAwaitingDeletionAuthorization = false
    }

    func refreshCredentialState() async {
        guard let appleUserID = Auth.auth().currentUser?.providerData
            .first(where: { $0.providerID == "apple.com" })?
            .uid
        else {
            isSignedIn = false
            return
        }

        do {
            let state = try await credentialState(for: appleUserID)
            guard state == .authorized else {
                try? Auth.auth().signOut()
                isSignedIn = false
                return
            }
            isSignedIn = true
        } catch {
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
        } catch {
            let authError = error as NSError
            if authError.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
               let updatedCredential = authError.userInfo[AuthErrorUserInfoUpdatedCredentialKey]
                    as? AuthCredential
            {
                do {
                    _ = try await Auth.auth().signIn(with: updatedCredential)
                    isSignedIn = true
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
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await user.reauthenticate(with: credential)
            try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
            try await user.delete()
            isAwaitingDeletionAuthorization = false
            isSignedIn = false
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
