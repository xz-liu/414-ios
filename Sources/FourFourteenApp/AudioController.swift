import AVFoundation
import UIKit

@MainActor
final class AudioController {
    enum Sound: String, CaseIterable {
        case bombBang = "bomb_bang"
        case bombPop = "bomb_pop"
        case cannonBoom = "cannon_boom"
        case cardContact = "card_contact"
        case cardCut = "card_cut"
        case draw
        case error
        case pass
        case playcard
        case reaction
        case rocketLaunch = "rocket_launch"
        case shuffle
        case tap
    }

    var effectsEnabled = true

    private var effectPlayers: [Sound: AVAudioPlayer] = [:]
    private var effectURLs: [Sound: URL] = [:]
    private var oneShotPlayers: [UUID: AVAudioPlayer] = [:]
    private var musicPlayer: AVAudioPlayer?

    init() {
        configureSession()
        preloadEffects()
        prepareMusic()
    }

    func play(_ sound: Sound) {
        guard effectsEnabled else { return }
        playPrepared(sound)
        playHaptic(for: sound)
    }

    func playCard(effect: CardGameEffectDescriptor?) {
        guard effectsEnabled else { return }
        guard let effect else {
            playLayer(.playcard)
            playLayer(.cardContact, volumeMultiplier: 0.52, delayNanoseconds: 36_000_000)
            impact(.light, intensity: 0.28)
            return
        }

        switch effect.kind {
        case .bomb:
            playLayer(.bombPop, volumeMultiplier: 0.92, rate: 0.92)
            playLayer(.bombBang, volumeMultiplier: 0.96, rate: 0.90, delayNanoseconds: 42_000_000)
            playLayer(.reaction, volumeMultiplier: 0.52, rate: 0.72, delayNanoseconds: 96_000_000)
            impact(.heavy, intensity: 0.92)
            delayedImpact(.rigid, intensity: 0.55, delayNanoseconds: 70_000_000)
        case .mushroom:
            playLayer(.cannonBoom, volumeMultiplier: 1.0, rate: 0.82)
            playLayer(.bombBang, volumeMultiplier: 0.80, rate: 0.66, delayNanoseconds: 112_000_000)
            playLayer(.reaction, volumeMultiplier: 0.50, rate: 0.58, delayNanoseconds: 210_000_000)
            impact(.heavy, intensity: 1.0)
            delayedImpact(.heavy, intensity: 0.72, delayNanoseconds: 110_000_000)
            delayedNotification(.success, delayNanoseconds: 260_000_000)
        case .rocket:
            playLayer(.rocketLaunch, volumeMultiplier: 0.96, rate: 1.0)
            playLayer(.bombPop, volumeMultiplier: 0.56, rate: 1.18, delayNanoseconds: 72_000_000)
            playLayer(.reaction, volumeMultiplier: 0.62, rate: 0.76, delayNanoseconds: 230_000_000)
            impact(.medium, intensity: 0.74)
            delayedImpact(.heavy, intensity: 0.92, delayNanoseconds: 150_000_000)
        case .straightFlush, .steelPlate:
            playLayer(.reaction, volumeMultiplier: 0.82, rate: 0.94)
            playLayer(.cardCut, volumeMultiplier: 0.56, rate: 0.84, delayNanoseconds: 48_000_000)
            impact(.medium, intensity: 0.62)
        case .airplane:
            playLayer(.draw, volumeMultiplier: 0.76, rate: 1.22)
            playLayer(.cardCut, volumeMultiplier: 0.46, rate: 1.20, delayNanoseconds: 60_000_000)
            impact(.soft, intensity: 0.38)
        case .straightTrail, .pairChain:
            playLayer(.playcard, volumeMultiplier: 0.82, rate: 1.04)
            playLayer(.cardContact, volumeMultiplier: 0.46, delayNanoseconds: 34_000_000)
            impact(.light, intensity: 0.34)
        case .stamp:
            playLayer(.reaction, volumeMultiplier: 0.95, rate: 1.04)
            impact(.rigid, intensity: 0.78)
        }
    }

    private func playPrepared(_ sound: Sound) {
        guard let player = effectPlayers[sound] else { return }
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
            effectURLs[sound] = url

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.enableRate = true
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
        case .bombBang, .bombPop, .cannonBoom, .rocketLaunch:
            return 0.92
        case .cardContact, .cardCut:
            return 0.68
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

    private func playLayer(
        _ sound: Sound,
        volumeMultiplier: Float = 1.0,
        rate: Float = 1.0,
        delayNanoseconds: UInt64 = 0
    ) {
        guard effectsEnabled else { return }
        if delayNanoseconds == 0 {
            playOneShot(sound, volumeMultiplier: volumeMultiplier, rate: rate)
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                playOneShot(sound, volumeMultiplier: volumeMultiplier, rate: rate)
            }
        }
    }

    private func playOneShot(_ sound: Sound, volumeMultiplier: Float, rate: Float) {
        guard effectsEnabled else { return }
        guard let url = effectURLs[sound] else {
            playPrepared(sound)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = max(0.5, min(1.8, rate))
            player.volume = min(1.0, volume(for: sound) * volumeMultiplier)
            player.prepareToPlay()

            let id = UUID()
            oneShotPlayers[id] = player
            player.play()
            let lifetime = UInt64((player.duration / Double(player.rate) + 0.20) * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: lifetime)
                oneShotPlayers[id] = nil
            }
        } catch {
            playPrepared(sound)
        }
    }

    private func playHaptic(for sound: Sound) {
        switch sound {
        case .tap, .draw, .cardContact, .cardCut:
            impact(.light, intensity: 0.24)
        case .playcard:
            impact(.light, intensity: 0.30)
        case .pass:
            impact(.soft, intensity: 0.22)
        case .shuffle:
            impact(.soft, intensity: 0.34)
        case .reaction:
            impact(.medium, intensity: 0.56)
        case .bombBang, .bombPop:
            impact(.heavy, intensity: 0.88)
        case .cannonBoom:
            impact(.heavy, intensity: 1.0)
        case .rocketLaunch:
            impact(.medium, intensity: 0.72)
        case .error:
            notification(.error)
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: min(1, max(0, intensity)))
    }

    private func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private func delayedImpact(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle,
        intensity: CGFloat,
        delayNanoseconds: UInt64
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard effectsEnabled else { return }
            impact(style, intensity: intensity)
        }
    }

    private func delayedNotification(
        _ type: UINotificationFeedbackGenerator.FeedbackType,
        delayNanoseconds: UInt64
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard effectsEnabled else { return }
            notification(type)
        }
    }
}
