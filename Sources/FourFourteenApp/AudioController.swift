import AVFoundation

@MainActor
final class AudioController {
    enum Sound: String, CaseIterable {
        case draw
        case error
        case pass
        case playcard
        case reaction
        case shuffle
        case tap
    }

    var effectsEnabled = true

    private var effectPlayers: [Sound: AVAudioPlayer] = [:]
    private var musicPlayer: AVAudioPlayer?

    init() {
        configureSession()
        preloadEffects()
        prepareMusic()
    }

    func play(_ sound: Sound) {
        guard effectsEnabled, let player = effectPlayers[sound] else { return }
        player.stop()
        player.currentTime = 0
        player.play()
    }

    func setMusicEnabled(_ enabled: Bool) {
        guard let player = musicPlayer else { return }
        if enabled {
            player.play()
        } else {
            player.pause()
        }
    }

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Audio is optional; gameplay should continue if the session cannot be configured.
        }
    }

    private func preloadEffects() {
        for sound in Sound.allCases {
            guard let url = Bundle.main.url(
                forResource: sound.rawValue,
                withExtension: "wav",
                subdirectory: "audio"
            ) else { continue }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = volume(for: sound)
                player.prepareToPlay()
                effectPlayers[sound] = player
            } catch {
                continue
            }
        }
    }

    private func prepareMusic() {
        guard let url = Bundle.main.url(
            forResource: "background",
            withExtension: "mp3",
            subdirectory: "audio"
        ) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.16
            player.prepareToPlay()
            musicPlayer = player
        } catch {
            musicPlayer = nil
        }
    }

    private func volume(for sound: Sound) -> Float {
        switch sound {
        case .reaction:
            return 0.95
        case .shuffle:
            return 0.65
        case .error:
            return 0.72
        default:
            return 0.78
        }
    }
}
