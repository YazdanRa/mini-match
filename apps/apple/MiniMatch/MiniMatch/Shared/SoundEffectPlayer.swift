import AVFAudio
import Foundation
import OSLog

enum SoundEffect: String, CaseIterable, Sendable {
    case mainButton = "bloop"
    case winner
    case noWinner = "no_winner"

    init(result: GameRoundResult) {
        self = result.winnerPlayerID == nil ? .noWinner : .winner
    }
}

actor SoundEffectPlayer {
    static let shared = SoundEffectPlayer()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MiniMatch",
        category: "SoundEffect"
    )
    private var players: [SoundEffect: AVAudioPlayer] = [:]

    private init(bundle: Bundle = .main) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            logger.error("Could not configure sound effects: \(error.localizedDescription)")
        }

        for sound in SoundEffect.allCases {
            guard let url = bundle.url(forResource: sound.rawValue, withExtension: "wav") else {
                logger.error("Missing sound effect: \(sound.rawValue).wav")
                continue
            }

            do {
                players[sound] = try AVAudioPlayer(contentsOf: url)
            } catch {
                logger.error("Could not load \(sound.rawValue).wav: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func play(_ sound: SoundEffect) {
        guard Self.soundEffectsEnabled else { return }
        Task {
            await performPlayback(sound)
        }
    }

    nonisolated func play(for result: GameRoundResult) {
        play(SoundEffect(result: result))
    }

    private func performPlayback(_ sound: SoundEffect) async {
        do {
            guard try await Self.activateAudioSession() else {
                logger.error("Could not activate audio for \(sound.rawValue).wav")
                return
            }
        } catch {
            logger.error("Could not activate audio for \(sound.rawValue).wav: \(error.localizedDescription)")
            return
        }

        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    nonisolated private static func activateAudioSession() async throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static var soundEffectsEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true
    }
}
