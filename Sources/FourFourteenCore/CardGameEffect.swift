import Foundation

public enum CardGameEffectKind: String, Codable, Sendable, Equatable {
    case bomb
    case mushroom
    case rocket
    case airplane
    case straightTrail
    case pairChain
    case steelPlate
    case straightFlush
    case stamp
}

public enum CardGameEffectIntensity: String, Codable, Sendable, Equatable, Comparable {
    case c
    case b
    case a
    case s

    public static func < (lhs: CardGameEffectIntensity, rhs: CardGameEffectIntensity) -> Bool {
        lhs.sortValue < rhs.sortValue
    }

    public var durationNanoseconds: UInt64 {
        switch self {
        case .c:
            return 800_000_000
        case .b:
            return 900_000_000
        case .a:
            return 1_050_000_000
        case .s:
            return 1_250_000_000
        }
    }

    public var isMajor: Bool {
        self == .a || self == .s
    }

    private var sortValue: Int {
        switch self {
        case .c: return 0
        case .b: return 1
        case .a: return 2
        case .s: return 3
        }
    }
}

public struct CardGameEffectDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let kind: CardGameEffectKind
    public let playerIndex: Int
    public let title: String
    public let subtitle: String
    public let intensity: CardGameEffectIntensity

    public init(
        id: UUID = UUID(),
        kind: CardGameEffectKind,
        playerIndex: Int,
        title: String,
        subtitle: String,
        intensity: CardGameEffectIntensity
    ) {
        self.id = id
        self.kind = kind
        self.playerIndex = playerIndex
        self.title = title
        self.subtitle = subtitle
        self.intensity = intensity
    }
}

public enum CardGameEffectMapper {
    public static func effect(for record: PlayRecord) -> CardGameEffectDescriptor? {
        switch record.kind {
        case .cha:
            return descriptor(.stamp, record: record, title: "叉!", intensity: .c)
        case .gou:
            return descriptor(.stamp, record: record, title: "勾!", intensity: .c)
        case .normal:
            guard let combination = record.combination else { return nil }
            switch combination.kind {
            case .sameRankBomb:
                if combination.sameRankCount >= 6 {
                    return descriptor(.mushroom, record: record, title: combination.displayName, intensity: .s)
                }
                return descriptor(.bomb, record: record, title: combination.displayName, intensity: .a)
            case .doubleJoker:
                return descriptor(.mushroom, record: record, title: "双王", intensity: .s)
            case .rocket414:
                return descriptor(.rocket, record: record, title: "4A4", subtitle: "\(record.playerName) · 火箭升空", intensity: .s)
            case .singleRun:
                return descriptor(.straightTrail, record: record, title: "单龙", intensity: .b)
            case .pairRun:
                return descriptor(.pairChain, record: record, title: "双龙", intensity: .b)
            case .triadWithSingle, .triadWithPair:
                return descriptor(.stamp, record: record, title: combination.displayName, intensity: .c)
            case .single, .pair, .cha, .gou:
                return nil
            }
        case .pass, .system:
            return nil
        }
    }

    public static func effect(for record: DouDizhuPlayRecord) -> CardGameEffectDescriptor? {
        guard record.kind == .play, let combination = record.combination else { return nil }
        switch combination.kind {
        case .bomb:
            return descriptor(.bomb, record: record, title: "炸弹", intensity: .a)
        case .rocket:
            return descriptor(.mushroom, record: record, title: "王炸", intensity: .s)
        case .airplane, .airplaneWithSingles, .airplaneWithPairs:
            return descriptor(.airplane, record: record, title: combination.displayName, intensity: .b)
        case .singleStraight:
            return descriptor(.straightTrail, record: record, title: "顺子", intensity: .b)
        case .pairStraight:
            return descriptor(.pairChain, record: record, title: "连对", intensity: .b)
        case .fourWithTwoSingles, .fourWithTwoPairs, .trioWithSingle, .trioWithPair:
            return descriptor(.stamp, record: record, title: combination.displayName, intensity: .c)
        case .single, .pair, .trio:
            return nil
        }
    }

    public static func effect(for record: RunFastPlayRecord) -> CardGameEffectDescriptor? {
        guard record.kind == .play, let combination = record.combination else { return nil }
        switch combination.kind {
        case .bomb:
            return descriptor(.bomb, record: record, title: "炸弹", intensity: .a)
        case .airplane, .airplaneWithWings:
            return descriptor(.airplane, record: record, title: combination.displayName, intensity: .b)
        case .singleStraight:
            return descriptor(.straightTrail, record: record, title: "顺子", intensity: .b)
        case .pairStraight:
            return descriptor(.pairChain, record: record, title: "连对", intensity: .b)
        case .trioWithTwo:
            return descriptor(.stamp, record: record, title: "三带二", intensity: .c)
        case .single, .pair, .trio:
            return nil
        }
    }

    public static func effect(for record: GuanDanPlayRecord) -> CardGameEffectDescriptor? {
        guard record.kind == .play, let combination = record.combination else { return nil }
        switch combination.kind {
        case .bomb:
            if combination.bombCount >= 6 {
                return descriptor(.mushroom, record: record, title: combination.displayName, intensity: .s)
            }
            return descriptor(.bomb, record: record, title: combination.displayName, intensity: .a)
        case .jokerBomb:
            return descriptor(.mushroom, record: record, title: "四王炸", intensity: .s)
        case .straightFlush:
            return descriptor(.straightFlush, record: record, title: "同花顺", intensity: .a)
        case .steelPlate:
            return descriptor(.steelPlate, record: record, title: "钢板", intensity: .a)
        case .singleStraight:
            return descriptor(.straightTrail, record: record, title: "顺子", intensity: .b)
        case .pairStraight:
            return descriptor(.pairChain, record: record, title: "连对", intensity: .b)
        case .trioWithPair:
            return descriptor(.stamp, record: record, title: "三带二", intensity: .c)
        case .single, .pair, .trio:
            return nil
        }
    }

    private static func descriptor(
        _ kind: CardGameEffectKind,
        record: PlayRecord,
        title: String,
        subtitle: String? = nil,
        intensity: CardGameEffectIntensity
    ) -> CardGameEffectDescriptor {
        CardGameEffectDescriptor(
            kind: kind,
            playerIndex: record.playerIndex,
            title: title,
            subtitle: subtitle ?? record.playerName,
            intensity: intensity
        )
    }

    private static func descriptor(
        _ kind: CardGameEffectKind,
        record: DouDizhuPlayRecord,
        title: String,
        intensity: CardGameEffectIntensity
    ) -> CardGameEffectDescriptor {
        CardGameEffectDescriptor(
            kind: kind,
            playerIndex: record.playerIndex,
            title: title,
            subtitle: record.playerName,
            intensity: intensity
        )
    }

    private static func descriptor(
        _ kind: CardGameEffectKind,
        record: RunFastPlayRecord,
        title: String,
        intensity: CardGameEffectIntensity
    ) -> CardGameEffectDescriptor {
        CardGameEffectDescriptor(
            kind: kind,
            playerIndex: record.playerIndex,
            title: title,
            subtitle: record.playerName,
            intensity: intensity
        )
    }

    private static func descriptor(
        _ kind: CardGameEffectKind,
        record: GuanDanPlayRecord,
        title: String,
        intensity: CardGameEffectIntensity
    ) -> CardGameEffectDescriptor {
        CardGameEffectDescriptor(
            kind: kind,
            playerIndex: record.playerIndex,
            title: title,
            subtitle: record.playerName,
            intensity: intensity
        )
    }
}
