import AVFAudio
import OSLog

enum RoundResultSound: String, CaseIterable {
    case winner
    case noWinner = "no_winner"

    init(result: GameRoundResult) {
        self = result.winnerPlayerID == nil ? .noWinner : .winner
    }
}

@MainActor
final class RoundResultSoundPlayer {
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
                player.prepareToPlay()
                players[sound] = player
            } catch {
                logger.error("Could not load \(sound.rawValue).wav: \(error.localizedDescription)")
            }
        }
    }

    func play(for result: GameRoundResult) {
        let sound = RoundResultSound(result: result)
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
