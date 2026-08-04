import AVFAudio
import OSLog

enum RoundResultSound: String, CaseIterable {
    case winner
    case noWinner = "no_winner"

    init(result: GameRoundResult) {
        self = result.winnerPlayerID == nil ? .noWinner : .winner
    }
}

actor RoundResultSoundPlayer {
    static let shared = RoundResultSoundPlayer()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MiniMatch",
        category: "RoundResultSound"
    )
    private var players: [RoundResultSound: AVAudioPlayer] = [:]

    private init(bundle: Bundle = .main) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            logger.error("Could not configure round-result audio: \(error.localizedDescription)")
        }

        for sound in RoundResultSound.allCases {
            guard let url = bundle.url(forResource: sound.rawValue, withExtension: "wav") else {
                logger.error("Missing round-result sound: \(sound.rawValue).wav")
                continue
            }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                players[sound] = player
            } catch {
                logger.error("Could not load \(sound.rawValue).wav: \(error.localizedDescription)")
            }
        }
    }

    func play(for result: GameRoundResult) async {
        do {
            guard try await Self.activateAudioSession() else {
                logger.error("Could not activate round-result audio")
                return
            }
        } catch {
            logger.error("Could not activate round-result audio: \(error.localizedDescription)")
            return
        }

        let sound = RoundResultSound(result: result)
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    nonisolated private static func activateAudioSession() async throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            return try await session.activate(options: [])
        }

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
}
