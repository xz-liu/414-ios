import Foundation

public struct DouDizhuPlayer: Hashable, Codable, Sendable {
    public let name: String
    public let isHuman: Bool

    public init(name: String, isHuman: Bool) {
        self.name = name
        self.isHuman = isHuman
    }
}

public enum DouDizhuPhase: String, Codable, Sendable {
    case bidding
    case playing
    case noLandlord
    case gameOver
}

public enum DouDizhuTeam: String, Codable, Sendable {
    case landlord
    case farmers
}

public enum DouDizhuCombinationKind: String, Codable, Sendable {
    case single
    case pair
    case trio
    case trioWithSingle
    case trioWithPair
    case singleStraight
    case pairStraight
    case airplane
    case airplaneWithSingles
    case airplaneWithPairs
    case fourWithTwoSingles
    case fourWithTwoPairs
    case bomb
    case rocket
}

public struct DouDizhuCombination: Hashable, Codable, Sendable {
    public let kind: DouDizhuCombinationKind
    public let cards: [Card]
    public let primaryRank: Rank
    public let sequenceLength: Int

    public init(
        kind: DouDizhuCombinationKind,
        cards: [Card],
        primaryRank: Rank,
        sequenceLength: Int = 0
    ) {
        self.kind = kind
        self.cards = cards.sortedForHand()
        self.primaryRank = primaryRank
        self.sequenceLength = sequenceLength
    }

    public var isBombLike: Bool {
        kind == .bomb || kind == .rocket
    }

    public var displayName: String {
        switch kind {
        case .single:
            return "单张"
        case .pair:
            return "对子"
        case .trio:
            return "三张"
        case .trioWithSingle:
            return "三带一"
        case .trioWithPair:
            return "三带二"
        case .singleStraight:
            return "顺子"
        case .pairStraight:
            return "连对"
        case .airplane:
            return "飞机"
        case .airplaneWithSingles:
            return "飞机带单"
        case .airplaneWithPairs:
            return "飞机带对"
        case .fourWithTwoSingles:
            return "四带二"
        case .fourWithTwoPairs:
            return "四带两对"
        case .bomb:
            return "炸弹"
        case .rocket:
            return "王炸"
        }
    }
}

public enum DouDizhuAction: Hashable, Sendable {
    case play([Card])
    case pass

    public var cards: [Card] {
        switch self {
        case .play(let cards):
            return cards
        case .pass:
            return []
        }
    }
}

public enum DouDizhuBidAction: Hashable, Sendable {
    case pass
    case bid(Int)
}

public enum DouDizhuEventKind: String, Codable, Sendable {
    case bid
    case landlord
    case play
    case pass
    case system
}

public struct DouDizhuPlayRecord: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let combination: DouDizhuCombination?
    public let kind: DouDizhuEventKind
    public let message: String

    public init(
        playerIndex: Int,
        playerName: String,
        combination: DouDizhuCombination?,
        kind: DouDizhuEventKind,
        message: String
    ) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.combination = combination
        self.kind = kind
        self.message = message
    }
}

public struct DouDizhuScoreLine: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let team: DouDizhuTeam
    public let delta: Int
    public let notes: [String]

    public init(playerIndex: Int, playerName: String, team: DouDizhuTeam, delta: Int, notes: [String]) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.team = team
        self.delta = delta
        self.notes = notes
    }
}

public struct DouDizhuState: Hashable, Codable, Sendable {
    public var players: [DouDizhuPlayer]
    public var hands: [[Card]]
    public var bottomCards: [Card]
    public var phase: DouDizhuPhase
    public var currentPlayerIndex: Int
    public var landlordIndex: Int?
    public var highestBid: Int
    public var highestBidderIndex: Int?
    public var bidTurnCount: Int
    public var lastPlay: DouDizhuPlayRecord?
    public var visibleRecord: DouDizhuPlayRecord?
    public var tableRecords: [DouDizhuPlayRecord?]
    public var passCount: Int
    public var multiplier: Int
    public var playActionCounts: [Int]
    public var winnerTeam: DouDizhuTeam?
    public var scores: [DouDizhuScoreLine]
    public var eventLog: [DouDizhuPlayRecord]

    public var isGameOver: Bool {
        phase == .gameOver
    }

    public init(
        players: [DouDizhuPlayer],
        hands: [[Card]],
        bottomCards: [Card],
        phase: DouDizhuPhase = .bidding,
        currentPlayerIndex: Int = 0,
        landlordIndex: Int? = nil,
        highestBid: Int = 0,
        highestBidderIndex: Int? = nil,
        bidTurnCount: Int = 0,
        lastPlay: DouDizhuPlayRecord? = nil,
        visibleRecord: DouDizhuPlayRecord? = nil,
        tableRecords: [DouDizhuPlayRecord?]? = nil,
        passCount: Int = 0,
        multiplier: Int = 1,
        playActionCounts: [Int]? = nil,
        winnerTeam: DouDizhuTeam? = nil,
        scores: [DouDizhuScoreLine] = [],
        eventLog: [DouDizhuPlayRecord] = []
    ) {
        self.players = players
        self.hands = hands.map { $0.sortedForHand() }
        self.bottomCards = bottomCards.sortedForHand()
        self.phase = phase
        self.currentPlayerIndex = currentPlayerIndex
        self.landlordIndex = landlordIndex
        self.highestBid = highestBid
        self.highestBidderIndex = highestBidderIndex
        self.bidTurnCount = bidTurnCount
        self.lastPlay = lastPlay
        self.visibleRecord = visibleRecord
        self.tableRecords = tableRecords ?? Array(repeating: nil, count: players.count)
        self.passCount = passCount
        self.multiplier = multiplier
        self.playActionCounts = playActionCounts ?? Array(repeating: 0, count: players.count)
        self.winnerTeam = winnerTeam
        self.scores = scores
        self.eventLog = eventLog
    }
}

public enum DouDizhuError: Error, Equatable, Sendable {
    case gameOver
    case notPlayersTurn
    case wrongPhase
    case illegalBid
    case illegalAction
    case cardsNotInHand
    case invalidCombination
    case cannotBeatPrevious
    case cannotPassOnLead
}
