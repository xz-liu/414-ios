import Foundation

public enum CombinationKind: String, Codable, Sendable {
    case single
    case pair
    case sameRankBomb
    case triadWithSingle
    case triadWithPair
    case singleRun
    case pairRun
    case doubleJoker
    case rocket414
    case cha
    case gou
}

public struct Combination: Hashable, Codable, Sendable {
    public let kind: CombinationKind
    public let cards: [Card]
    public let primaryRank: Rank?
    public let sameRankCount: Int
    public let sequenceLength: Int

    public init(
        kind: CombinationKind,
        cards: [Card],
        primaryRank: Rank?,
        sameRankCount: Int = 0,
        sequenceLength: Int = 0
    ) {
        self.kind = kind
        self.cards = cards.sortedForHand()
        self.primaryRank = primaryRank
        self.sameRankCount = sameRankCount
        self.sequenceLength = sequenceLength
    }

    public var isBombLike: Bool {
        switch kind {
        case .sameRankBomb, .doubleJoker, .rocket414:
            return true
        default:
            return false
        }
    }

    public var cannotBeBeaten: Bool {
        kind == .rocket414 || kind == .cha || kind == .gou
    }

    public var displayName: String {
        switch kind {
        case .single:
            return "单张"
        case .pair:
            return "对子"
        case .sameRankBomb:
            if sameRankCount == 3 { return "炸" }
            if sameRankCount == 4 { return "炮" }
            return "\(sameRankCount)同张炸"
        case .triadWithSingle:
            return "三带一"
        case .triadWithPair:
            return "三带二"
        case .singleRun:
            return "单龙"
        case .pairRun:
            return "双龙"
        case .doubleJoker:
            return "双王"
        case .rocket414:
            return "4A4火箭"
        case .cha:
            return "叉"
        case .gou:
            return "勾"
        }
    }
}

public enum PlayerAction: Hashable, Sendable {
    case play([Card])
    case pass
    case cha([Card])
    case gou(Card)

    public var cards: [Card] {
        switch self {
        case .play(let cards), .cha(let cards):
            return cards
        case .gou(let card):
            return [card]
        case .pass:
            return []
        }
    }
}

public enum PromptKind: String, Codable, Sendable {
    case lead
    case follow
    case cha
    case gou
    case gameOver
}

public struct TurnPrompt: Hashable, Codable, Sendable {
    public let kind: PromptKind
    public let playerIndex: Int?
    public let baseRank: Rank?

    public init(kind: PromptKind, playerIndex: Int?, baseRank: Rank? = nil) {
        self.kind = kind
        self.playerIndex = playerIndex
        self.baseRank = baseRank
    }

    public static let gameOver = TurnPrompt(kind: .gameOver, playerIndex: nil)
}

public enum PlayEventKind: String, Codable, Sendable {
    case normal
    case pass
    case cha
    case gou
    case system
}

public struct PlayRecord: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let combination: Combination?
    public let kind: PlayEventKind
    public let message: String

    public init(
        playerIndex: Int,
        playerName: String,
        combination: Combination?,
        kind: PlayEventKind,
        message: String
    ) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.combination = combination
        self.kind = kind
        self.message = message
    }
}
