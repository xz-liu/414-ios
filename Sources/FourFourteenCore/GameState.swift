import Foundation

public struct GamePlayer: Hashable, Codable, Sendable {
    public let name: String
    public let isHuman: Bool

    public init(name: String, isHuman: Bool) {
        self.name = name
        self.isHuman = isHuman
    }
}

public struct ScoreLine: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let remainingCards: Int
    public let multiplier: Int
    public let penalty: Int
    public let notes: [String]

    public init(
        playerIndex: Int,
        playerName: String,
        remainingCards: Int,
        multiplier: Int,
        penalty: Int,
        notes: [String]
    ) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.remainingCards = remainingCards
        self.multiplier = multiplier
        self.penalty = penalty
        self.notes = notes
    }
}

public struct GameState: Hashable, Codable, Sendable {
    public var deckCount: Int
    public var players: [GamePlayer]
    public var hands: [[Card]]
    public var prompt: TurnPrompt
    public var lastPlayableRecord: PlayRecord?
    public var visibleRecord: PlayRecord?
    public var eventLog: [PlayRecord]
    public var passCount: Int
    public var cardsPlayedCount: [Int]
    public var winnerIndex: Int?
    public var scores: [ScoreLine]

    public var isGameOver: Bool {
        winnerIndex != nil
    }

    public init(
        deckCount: Int,
        players: [GamePlayer],
        hands: [[Card]],
        prompt: TurnPrompt,
        lastPlayableRecord: PlayRecord? = nil,
        visibleRecord: PlayRecord? = nil,
        eventLog: [PlayRecord] = [],
        passCount: Int = 0,
        cardsPlayedCount: [Int]? = nil,
        winnerIndex: Int? = nil,
        scores: [ScoreLine] = []
    ) {
        self.deckCount = deckCount
        self.players = players
        self.hands = hands.map { $0.sortedForHand() }
        self.prompt = prompt
        self.lastPlayableRecord = lastPlayableRecord
        self.visibleRecord = visibleRecord
        self.eventLog = eventLog
        self.passCount = passCount
        self.cardsPlayedCount = cardsPlayedCount ?? Array(repeating: 0, count: players.count)
        self.winnerIndex = winnerIndex
        self.scores = scores
    }
}

public enum GameError: Error, Equatable, Sendable {
    case gameOver
    case notPlayersTurn
    case illegalAction
    case cardsNotInHand
    case invalidCombination
    case cannotBeatPrevious
    case cannotPassOnLead
}
