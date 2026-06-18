import SwiftUI
import UIKit

struct TableEffectOverlay: View {
    let effect: CardGameEffectDescriptor?
    let seatCount: Int

    var body: some View {
        GeometryReader { proxy in
            if let effect {
                TableEffectHost(
                    effect: effect,
                    seatCount: seatCount,
                    canvasSize: proxy.size
                )
                .id(effect.id)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TableEffectHost: View {
    let effect: CardGameEffectDescriptor
    let seatCount: Int
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            if !reduceMotion, usesImpactBackdrop {
                TableImpactBackdrop(
                    effect: effect,
                    anchorPoint: anchorPoint,
                    canvasSize: canvasSize,
                    phase: phase
                )
            }

            if reduceMotion {
                ReducedMotionEffect(effect: effect)
                    .position(anchorPoint)
            } else {
                effectBody
                    .position(anchorPoint)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: duration)) {
                phase = 1
            }
        }
    }

    @ViewBuilder
    private var effectBody: some View {
        switch effect.kind {
        case .bomb:
            BombBurstEffect(effect: effect, phase: phase)
        case .mushroom:
            MushroomCloudEffect(effect: effect, phase: phase)
        case .rocket:
            RocketLaunchEffect(effect: effect, phase: phase)
        case .airplane:
            AirplanePassEffect(effect: effect, phase: phase)
        case .straightTrail:
            StraightTrailEffect(effect: effect, phase: phase)
        case .pairChain:
            PairChainEffect(effect: effect, phase: phase)
        case .steelPlate:
            SteelPlateEffect(effect: effect, phase: phase)
        case .straightFlush:
            StraightFlushEffect(effect: effect, phase: phase)
        case .stamp:
            StampEffect(effect: effect, phase: phase)
        }
    }

    private var duration: Double {
        Double(effect.intensity.durationNanoseconds) / 1_000_000_000
    }

    private var usesImpactBackdrop: Bool {
        effect.kind == .bomb || effect.kind == .mushroom || effect.kind == .rocket
    }

    private var anchorPoint: CGPoint {
        let x: CGFloat
        let y: CGFloat
        if seatCount == 4 {
            switch effect.playerIndex {
            case 0:
                x = 0.50
                y = 0.74
            case 1:
                x = 0.28
                y = 0.49
            case 2:
                x = 0.50
                y = 0.27
            case 3:
                x = 0.72
                y = 0.49
            default:
                x = 0.50
                y = 0.50
            }
        } else {
            switch effect.playerIndex {
            case 0:
                x = 0.50
                y = 0.74
            case 1:
                x = 0.30
                y = 0.43
            case 2:
                x = 0.70
                y = 0.43
            default:
                x = 0.50
                y = 0.50
            }
        }
        return CGPoint(x: canvasSize.width * x, y: canvasSize.height * y)
    }
}

private struct TableImpactBackdrop: View {
    let effect: CardGameEffectDescriptor
    let anchorPoint: CGPoint
    let canvasSize: CGSize
    let phase: CGFloat

    var body: some View {
        ZStack {
            Color.white
                .opacity(Double(flashOpacity))
                .blendMode(.screen)

            RadialGradient(
                colors: [
                    impactColor.opacity(0.46),
                    impactColor.opacity(0.18),
                    Color.black.opacity(0.30),
                    Color.clear
                ],
                center: gradientCenter,
                startRadius: 20,
                endRadius: max(canvasSize.width, canvasSize.height) * 0.58
            )
            .opacity(Double(max(0, 1 - phase * 0.72)))
            .blendMode(.screen)

            Color.black
                .opacity(Double(max(0, 0.20 - phase * 0.18)))

            ForEach(0..<3, id: \.self) { index in
                let localPhase = min(1, max(0, phase * 1.28 - CGFloat(index) * 0.16))
                Ellipse()
                    .stroke(
                        impactColor.opacity(Double(max(0, 0.48 - localPhase * 0.46))),
                        lineWidth: max(1, 7 - CGFloat(index) * 1.8)
                    )
                    .frame(
                        width: 120 + localPhase * (canvasSize.width * 0.46 + CGFloat(index) * 80),
                        height: 42 + localPhase * (canvasSize.height * 0.20 + CGFloat(index) * 22)
                    )
                    .position(anchorPoint)
                    .blendMode(.screen)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private var flashOpacity: CGFloat {
        switch effect.intensity {
        case .s:
            return max(0, 0.48 - phase * 2.9)
        case .a:
            return max(0, 0.32 - phase * 2.3)
        case .b, .c:
            return 0
        }
    }

    private var impactColor: Color {
        switch effect.kind {
        case .rocket:
            return Color(red: 1.0, green: 0.82, blue: 0.18)
        case .mushroom:
            return Color(red: 1.0, green: 0.58, blue: 0.08)
        default:
            return Color(red: 1.0, green: 0.36, blue: 0.05)
        }
    }

    private var gradientCenter: UnitPoint {
        UnitPoint(
            x: max(0, min(1, anchorPoint.x / max(1, canvasSize.width))),
            y: max(0, min(1, anchorPoint.y / max(1, canvasSize.height)))
        )
    }
}

private struct ImpactRings: View {
    let phase: CGFloat
    let color: Color
    let maxSize: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let localPhase = min(1, max(0, phase * 1.22 - CGFloat(index) * 0.18))
                Ellipse()
                    .stroke(
                        color.opacity(Double(max(0, 0.78 - localPhase * 0.84))),
                        lineWidth: max(1.2, 6.5 - CGFloat(index) * 1.7)
                    )
                    .frame(
                        width: 50 + localPhase * (maxSize + CGFloat(index) * 34),
                        height: 24 + localPhase * (maxSize * 0.44 + CGFloat(index) * 16)
                    )
                    .blendMode(.screen)
            }
        }
    }
}

private struct RadialBurstRays: View {
    let phase: CGFloat
    let color: Color
    let count: Int
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let angle = CGFloat(index) / CGFloat(max(1, count)) * .pi * 2
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                color.opacity(0.86),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: index.isMultiple(of: 2) ? 5 : 3, height: 34 + CGFloat(index % 4) * 7)
                    .offset(y: -(26 + phase * radius))
                    .rotationEffect(.radians(Double(angle)))
                    .opacity(Double(max(0, 0.90 - phase * 1.10)))
                    .scaleEffect(x: 0.72, y: 0.55 + phase * 1.05)
                    .blendMode(.screen)
            }
        }
    }
}

private struct BombBurstEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ImpactRings(
                phase: phase,
                color: Color(red: 1.0, green: 0.46, blue: 0.08),
                maxSize: 300
            )

            RadialBurstRays(
                phase: phase,
                color: Color(red: 1.0, green: 0.62, blue: 0.08),
                count: 18,
                radius: 114
            )

            EffectImageView(name: "flare")
                .frame(width: 238, height: 238)
                .scaleEffect(0.48 + phase * 1.42)
                .opacity(Double(max(0, 0.92 - phase * 1.06)))
                .blendMode(.screen)

            SpriteSheetFrameView(
                imageName: "explosion_big_sheet",
                columns: 4,
                rows: 4,
                frameCount: 16,
                progress: min(1, phase * 1.04)
            )
            .frame(width: 228, height: 228)
            .scaleEffect(0.62 + phase * 0.56)
            .saturation(1.25)
            .contrast(1.10)
            .shadow(color: .red.opacity(0.72), radius: 18)

            SpriteSheetFrameView(
                imageName: "explosion_sheet",
                columns: 10,
                rows: 5,
                frameCount: 50,
                progress: phase
            )
            .frame(width: 176, height: 176)
            .scaleEffect(0.70 + phase * 0.42)
            .brightness(0.08)
            .shadow(color: .orange.opacity(0.95), radius: 16)

            ParticleImageBurst(
                imageName: "spark",
                count: 26,
                phase: phase,
                radius: 148,
                size: 30,
                tint: .orange
            )

            EffectLabel(effect: effect, color: .orange)
                .scaleEffect(1.24 - phase * 0.10)
                .offset(y: 88 - phase * 16)
                .opacity(Double(max(0, 1 - phase * 0.08)))
        }
        .frame(width: 360, height: 260)
    }
}

private struct MushroomCloudEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ImpactRings(
                phase: phase,
                color: Color(red: 1.0, green: 0.70, blue: 0.10),
                maxSize: 360
            )
            .offset(y: 44)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.72),
                            Color.red.opacity(0.36),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .frame(width: 350, height: 120)
                .scaleEffect(x: 0.45 + phase * 1.08, y: 0.42 + phase * 0.35)
                .offset(y: 56)
                .opacity(Double(max(0, 0.86 - phase * 0.48)))
                .blendMode(.screen)

            SpriteSheetFrameView(
                imageName: "explosion_big_sheet",
                columns: 4,
                rows: 4,
                frameCount: 16,
                progress: min(1, phase * 0.96)
            )
            .frame(width: 250, height: 250)
            .scaleEffect(0.74 + phase * 0.56)
            .offset(y: -42)
            .saturation(1.30)
            .shadow(color: .orange.opacity(0.94), radius: 20)

            ForEach(0..<7, id: \.self) { index in
                EffectImageView(name: "smoke")
                    .frame(width: 78 + CGFloat(index) * 13, height: 78 + CGFloat(index) * 13)
                    .colorMultiply(index.isMultiple(of: 2) ? .gray : .white)
                    .opacity(Double(max(0, 0.74 - phase * 0.32)))
                    .scaleEffect(0.54 + phase * 0.92)
                    .offset(
                        x: CGFloat(index - 3) * 24,
                        y: -66 - phase * 34 + CGFloat(index % 2) * 18
                    )
            }

            EffectImageView(name: "flare")
                .frame(width: 270, height: 270)
                .opacity(Double(max(0, 0.86 - phase * 0.64)))
                .scaleEffect(0.42 + phase * 1.52)
                .blendMode(.screen)

            ParticleImageBurst(
                imageName: "spark",
                count: 22,
                phase: phase,
                radius: 170,
                size: 26,
                tint: .yellow
            )

            EffectLabel(effect: effect, color: .yellow)
                .scaleEffect(1.28 - phase * 0.12)
                .offset(y: 96)
        }
        .frame(width: 390, height: 290)
    }
}

private struct RocketLaunchEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ImpactRings(
                phase: phase,
                color: Color(red: 1.0, green: 0.78, blue: 0.16),
                maxSize: 300
            )
            .offset(y: 70)

            ForEach(0..<9, id: \.self) { index in
                EffectImageView(name: index.isMultiple(of: 2) ? "trace" : "spark")
                    .frame(width: 60 - CGFloat(index % 3) * 8, height: 24)
                    .rotationEffect(.degrees(90 + Double(index - 4) * 5))
                    .colorMultiply(index.isMultiple(of: 2) ? .orange : .yellow)
                    .offset(
                        x: CGFloat(index - 4) * 13,
                        y: 88 + phase * 64 + CGFloat(index % 2) * 12
                    )
                    .scaleEffect(0.62 + phase * 1.04)
                    .opacity(Double(max(0, 0.88 - phase * 0.78)))
                    .blendMode(.screen)
            }

            EffectImageView(name: "flare")
                .frame(width: 212, height: 212)
                .scaleEffect(0.36 + phase * 1.18)
                .offset(y: 78)
                .opacity(Double(max(0, 0.82 - phase * 0.82)))
                .blendMode(.screen)

            AnimatedImageSequenceView(
                names: ["thruster_1", "thruster_2", "thruster_3", "thruster_4"],
                progress: phase
            )
            .frame(width: 104, height: 86)
            .rotationEffect(.degrees(90))
            .scaleEffect(1.10 + phase * 1.55)
            .offset(x: -64, y: 66 - phase * 164)
            .opacity(Double(max(0, 1 - phase * 0.42)))
            .blendMode(.screen)

            EffectImageView(name: "missile")
                .frame(width: 164, height: 72)
                .rotationEffect(.degrees(-88))
                .offset(y: 70 - phase * 210)
                .scaleEffect(0.86 + phase * 0.38)
                .shadow(color: .yellow.opacity(0.92), radius: 12)
                .shadow(color: .orange.opacity(0.74), radius: 22)

            EffectLabel(effect: effect, color: Color(red: 1.0, green: 0.72, blue: 0.12))
                .scaleEffect(1.30 - phase * 0.10)
                .offset(y: 116)
                .opacity(Double(max(0, 1 - phase * 0.12)))
        }
        .frame(width: 340, height: 330)
    }
}

private struct AirplanePassEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                EffectImageView(name: "trace")
                    .frame(width: 72 - CGFloat(index) * 10, height: 24)
                    .rotationEffect(.degrees(90))
                    .opacity(Double(max(0, 0.50 - phase * 0.20)))
                    .offset(x: -94 - phase * 34 + CGFloat(index) * 20, y: CGFloat(index - 1) * 8)
            }

            AnimatedImageSequenceView(
                names: ["airplane_1", "airplane_2", "airplane_3", "airplane_4"],
                progress: phase
            )
            .frame(width: 112, height: 64)
            .rotationEffect(.degrees(-8))
            .offset(x: -96 + phase * 192, y: sin(phase * .pi) * -16)
            .shadow(color: Color.cyan.opacity(0.68), radius: 6)

            EffectLabel(effect: effect, color: .cyan)
                .offset(y: 52)
        }
        .frame(width: 240, height: 140)
    }
}

private struct StraightTrailEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                EffectImageView(name: index.isMultiple(of: 2) ? "trace" : "star")
                    .frame(width: index.isMultiple(of: 2) ? 58 : 30, height: index.isMultiple(of: 2) ? 22 : 30)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? 90 : 0))
                    .offset(
                        x: CGFloat(index - 3) * 24,
                        y: CGFloat(index - 3) * -8
                    )
                    .scaleEffect(0.35 + min(1, phase + CGFloat(index) * 0.08))
            }

            EffectImageView(name: "magic")
                .frame(width: 78, height: 78)
                .offset(x: 88 * phase - 44, y: -22 * phase)
                .opacity(Double(max(0.25, 1 - phase * 0.20)))

            EffectLabel(effect: effect, color: .green)
                .offset(y: 50)
        }
        .frame(width: 250, height: 140)
    }
}

private struct PairChainEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 3) {
                    EffectImageView(name: "magic")
                    EffectImageView(name: "magic")
                }
                .frame(width: 52, height: 24)
                .offset(x: CGFloat(index - 2) * 34, y: CGFloat(index % 2 == 0 ? -8 : 8))
                .scaleEffect(0.45 + phase * 0.65)
            }

            EffectLabel(effect: effect, color: .cyan)
                .offset(y: 48)
        }
        .frame(width: 230, height: 130)
    }
}

private struct SteelPlateEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                EffectImageView(name: "slash")
                    .frame(width: 126, height: 54)
                    .colorMultiply(.gray)
                    .offset(
                        x: (index == 0 ? -92 : 92) * (1 - phase),
                        y: CGFloat(index == 0 ? -12 : 14)
                    )
                    .rotationEffect(.degrees(index == 0 ? -4 : 4))
                    .shadow(color: .white.opacity(0.42), radius: 4)
            }

            EffectImageView(name: "spark")
                .frame(width: 66, height: 66)
                .scaleEffect(0.6 + phase * 0.55)
                .opacity(Double(max(0, 1 - phase * 0.35)))

            EffectLabel(effect: effect, color: .white)
                .offset(y: 54)
        }
        .frame(width: 240, height: 140)
    }
}

private struct StraightFlushEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                EffectImageView(name: index.isMultiple(of: 2) ? "star" : "magic")
                    .frame(width: 38 + CGFloat(index % 2) * 8, height: 38 + CGFloat(index % 2) * 8)
                    .colorMultiply(index.isMultiple(of: 2) ? .red : .yellow)
                    .offset(
                        x: CGFloat(index - 2) * 36,
                        y: sin((phase + CGFloat(index) * 0.12) * .pi) * -18
                    )
                    .scaleEffect(0.55 + phase * 0.72)
                    .shadow(color: Color.yellow.opacity(0.78), radius: 5)
            }

            Capsule()
                .fill(Color.yellow.opacity(0.88 - phase * 0.20))
                .frame(width: 180 * phase, height: 5)
                .offset(y: 22)

            EffectLabel(effect: effect, color: Color(red: 1.00, green: 0.78, blue: 0.18))
                .offset(y: 54)
        }
        .frame(width: 250, height: 150)
    }
}

private struct StampEffect: View {
    let effect: CardGameEffectDescriptor
    let phase: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(effect.title)
                .font(.system(size: effect.intensity == .c ? 42 : 48, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(effect.subtitle)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .foregroundStyle(stampColor)
        .shadow(color: stampColor.opacity(0.76), radius: 6)
        .shadow(color: .black.opacity(0.56), radius: 4, y: 2)
        .scaleEffect(0.45 + phase * 0.78)
        .rotationEffect(.degrees(-7 + Double(phase) * 7))
        .opacity(Double(max(0, 1 - max(0, phase - 0.82) * 4)))
        .frame(width: 190, height: 108)
    }

    private var stampColor: Color {
        if effect.title.contains("叉") {
            return Color(red: 1.00, green: 0.24, blue: 0.16)
        }
        if effect.title.contains("勾") {
            return Color(red: 1.00, green: 0.62, blue: 0.12)
        }
        return Color(red: 1.00, green: 0.78, blue: 0.22)
    }
}

private struct SpriteSheetFrameView: View {
    let imageName: String
    let columns: Int
    let rows: Int
    let frameCount: Int
    let progress: CGFloat

    var body: some View {
        if let image = EffectImageCache.spriteFrame(
            named: imageName,
            columns: columns,
            rows: rows,
            frameIndex: frameIndex
        ) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Color.clear
        }
    }

    private var frameIndex: Int {
        guard frameCount > 1 else { return 0 }
        let clamped = min(1, max(0, progress))
        return min(frameCount - 1, Int((clamped * CGFloat(frameCount - 1)).rounded(.down)))
    }
}

private struct AnimatedImageSequenceView: View {
    let names: [String]
    let progress: CGFloat

    var body: some View {
        EffectImageView(name: currentName)
    }

    private var currentName: String {
        guard !names.isEmpty else { return "" }
        let loopedIndex = Int(max(0, progress) * CGFloat(names.count * 8)) % names.count
        return names[loopedIndex]
    }
}

private struct EffectImageView: View {
    let name: String

    var body: some View {
        if let image = EffectImageCache.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}

private struct ParticleImageBurst: View {
    let imageName: String
    let count: Int
    let phase: CGFloat
    let radius: CGFloat
    let size: CGFloat
    let tint: Color

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            let angle = CGFloat(index) / CGFloat(max(count, 1)) * 2 * .pi
            EffectImageView(name: imageName)
                .frame(width: size, height: size)
                .colorMultiply(index.isMultiple(of: 2) ? tint : .yellow)
                .rotationEffect(.radians(Double(angle)))
                .offset(
                    x: cos(angle) * (18 + phase * radius),
                    y: sin(angle) * (14 + phase * radius * 0.72)
                )
                .scaleEffect(0.55 + phase * 0.70)
                .opacity(Double(max(0, 1 - phase * 1.15)))
        }
    }
}

private enum EffectImageCache {
    private static var images: [String: UIImage] = [:]
    private static var frames: [String: UIImage] = [:]

    static func image(named name: String) -> UIImage? {
        if let cached = images[name] {
            return cached
        }
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "effects/sprites"
        ),
              let image = UIImage(contentsOfFile: url.path)
        else {
            return nil
        }
        images[name] = image
        return image
    }

    static func spriteFrame(
        named name: String,
        columns: Int,
        rows: Int,
        frameIndex: Int
    ) -> UIImage? {
        let key = "\(name)-\(columns)-\(rows)-\(frameIndex)"
        if let cached = frames[key] {
            return cached
        }
        guard let image = image(named: name),
              let cgImage = image.cgImage,
              columns > 0,
              rows > 0
        else {
            return nil
        }

        let frameWidth = cgImage.width / columns
        let frameHeight = cgImage.height / rows
        let safeIndex = max(0, min(frameIndex, columns * rows - 1))
        let column = safeIndex % columns
        let row = safeIndex / columns
        let rect = CGRect(
            x: column * frameWidth,
            y: row * frameHeight,
            width: frameWidth,
            height: frameHeight
        )

        guard let cropped = cgImage.cropping(to: rect) else {
            return nil
        }
        let frame = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        frames[key] = frame
        return frame
    }
}

private struct ReducedMotionEffect: View {
    let effect: CardGameEffectDescriptor

    var body: some View {
        EffectLabel(effect: effect, color: color)
            .frame(width: 210, height: 100)
    }

    private var color: Color {
        switch effect.kind {
        case .bomb, .mushroom:
            return .orange
        case .rocket, .straightFlush, .stamp:
            return .yellow
        case .airplane, .pairChain:
            return .cyan
        case .straightTrail:
            return .green
        case .steelPlate:
            return .white
        }
    }
}

private struct EffectLabel: View {
    let effect: CardGameEffectDescriptor
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(effect.title)
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(effect.subtitle)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.white.opacity(0.86))
        }
        .foregroundStyle(color)
        .shadow(color: color.opacity(0.70), radius: 6)
        .shadow(color: .black.opacity(0.60), radius: 4, y: 2)
        .frame(width: 180)
    }

    private var titleSize: CGFloat {
        switch effect.intensity {
        case .s:
            return 32
        case .a:
            return 28
        case .b:
            return 24
        case .c:
            return 22
        }
    }
}
