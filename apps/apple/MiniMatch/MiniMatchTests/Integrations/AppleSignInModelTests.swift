import Foundation
import Testing
@testable import MiniMatch

struct AppleSignInModelTests {
    @Test @MainActor
    func profileDeletionConfirmationCanBeRequestedFromSettings() {
        let model = AppleSignInModel()

        model.requestProfileDeletionConfirmation()

        #expect(model.canDeleteProfile)
        #expect(model.isConfirmingDeletion)
    }

    @Test
    func appleSignInNonceIsSecurelyShaped() throws {
        let nonce = try AppleSignInModel.randomNonce()

        #expect(nonce.count == 32)
        #expect(nonce.allSatisfy {
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._".contains($0)
        })
        #expect(
            AppleSignInModel.sha256("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
