import Foundation

public enum Suit: String, CaseIterable, Codable, Sendable, Comparable {
    case diamonds
    case clubs
    case hearts
    case spades

    public var symbol: String {
        switch self {
        case .diamonds: return "D"
        case .clubs: return "C"
        case .hearts: return "H"
        case .spades: return "S"
        }
    }

    public var displaySymbol: String {
        switch self {
        case .diamonds: return "♦"
        case .clubs: return "♣"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    public var sortValue: Int {
        switch self {
        case .diamonds: return 0
        case .clubs: return 1
        case .hearts: return 2
        case .spades: return 3
        }
    }

    public static func < (lhs: Suit, rhs: Suit) -> Bool {
        lhs.sortValue < rhs.sortValue
    }
}

public enum Rank: Int, CaseIterable, Codable, Sendable, Comparable {
    case three = 0
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case ten
    case jack
    case queen
    case king
    case ace
    case two
    case smallJoker
    case bigJoker

    public var label: String {
        switch self {
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .ten: return "10"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        case .two: return "2"
        case .smallJoker: return "小王"
        case .bigJoker: return "大王"
        }
    }

    public var canBeInRun: Bool {
        rawValue <= Rank.ace.rawValue
    }

    public static var runRanks: [Rank] {
        [.three, .four, .five, .six, .seven, .eight, .nine, .ten, .jack, .queen, .king, .ace]
    }

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Card: Identifiable, Hashable, Codable, Sendable, Comparable {
    public let rank: Rank
    public let suit: Suit?
    public let deckIndex: Int

    public init(rank: Rank, suit: Suit?, deckIndex: Int) {
        self.rank = rank
        self.suit = suit
        self.deckIndex = deckIndex
    }

    public var id: String {
        let suitPart = suit?.rawValue ?? "joker"
        return "\(deckIndex)-\(rank.rawValue)-\(suitPart)"
    }

    public var displayText: String {
        if rank == .smallJoker || rank == .bigJoker {
            return rank.label
        }
        return "\(rank.label)\(suit?.displaySymbol ?? "")"
    }

    public var isRed: Bool {
        suit == .diamonds || suit == .hearts || rank == .bigJoker
    }

    public var isHeartThree: Bool {
        rank == .three && suit == .hearts
    }

    public static func < (lhs: Card, rhs: Card) -> Bool {
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        if lhs.suit != rhs.suit {
            return (lhs.suit?.sortValue ?? 4) < (rhs.suit?.sortValue ?? 4)
        }
        return lhs.deckIndex < rhs.deckIndex
    }
}

public struct DeckConfig: Hashable, Codable, Sendable {
    public let deckCount: Int

    public init(deckCount: Int) {
        precondition((1...4).contains(deckCount), "414 supports 1 to 4 decks.")
        self.deckCount = deckCount
    }

    public func makeDeck() -> [Card] {
        var cards: [Card] = []
        for deckIndex in 0..<deckCount {
            for rank in Rank.allCases where rank != .smallJoker && rank != .bigJoker {
                for suit in Suit.allCases {
                    cards.append(Card(rank: rank, suit: suit, deckIndex: deckIndex))
                }
            }
            cards.append(Card(rank: .smallJoker, suit: nil, deckIndex: deckIndex))
            cards.append(Card(rank: .bigJoker, suit: nil, deckIndex: deckIndex))
        }
        return cards
    }
}

public extension Array where Element == Card {
    func sortedForHand() -> [Card] {
        sorted()
    }

    func count(of rank: Rank) -> Int {
        filter { $0.rank == rank }.count
    }

    func containsRocket414() -> Bool {
        count(of: .four) >= 2 && count(of: .ace) >= 1
    }

    func rocket414Cards() -> [Card]? {
        let fours = sortedForHand().filter { $0.rank == .four }
        let aces = sortedForHand().filter { $0.rank == .ace }
        guard fours.count >= 2, let ace = aces.first else { return nil }
        return (Array(fours.prefix(2)) + [ace]).sortedForHand()
    }

    func rocket414Count() -> Int {
        Swift.min(count(of: .four) / 2, count(of: .ace))
    }

    func containsDoubleJoker() -> Bool {
        count(of: .smallJoker) >= 1 && count(of: .bigJoker) >= 1
    }
}
