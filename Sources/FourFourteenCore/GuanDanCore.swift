import Foundation

public struct GuanDanPlayer: Hashable, Codable, Sendable {
    public let name: String
    public let isHuman: Bool

    public init(name: String, isHuman: Bool) {
        self.name = name
        self.isHuman = isHuman
    }
}

public enum GuanDanPhase: String, Codable, Sendable {
    case playing
    case gameOver
}

public enum GuanDanTeam: String, Codable, Sendable {
    case teamA
    case teamB
}

public enum GuanDanCombinationKind: String, Codable, Sendable {
    case single
    case pair
    case trio
    case trioWithPair
    case singleStraight
    case pairStraight
    case steelPlate
    case bomb
    case straightFlush
    case jokerBomb
}

public struct GuanDanCombination: Hashable, Codable, Sendable {
    public let kind: GuanDanCombinationKind
    public let cards: [Card]
    public let primaryRank: Rank
    public let sequenceLength: Int
    public let bombCount: Int
    public let usesWildCards: Bool

    public init(
        kind: GuanDanCombinationKind,
        cards: [Card],
        primaryRank: Rank,
        sequenceLength: Int = 0,
        bombCount: Int = 0,
        usesWildCards: Bool = false
    ) {
        self.kind = kind
        self.cards = cards.sortedForHand()
        self.primaryRank = primaryRank
        self.sequenceLength = sequenceLength
        self.bombCount = bombCount
        self.usesWildCards = usesWildCards
    }

    public var isBombLike: Bool {
        switch kind {
        case .bomb, .straightFlush, .jokerBomb:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch kind {
        case .single:
            return "单张"
        case .pair:
            return "对子"
        case .trio:
            return "三张"
        case .trioWithPair:
            return "三带二"
        case .singleStraight:
            return "顺子"
        case .pairStraight:
            return "连对"
        case .steelPlate:
            return "钢板"
        case .bomb:
            return "\(bombCount)张炸"
        case .straightFlush:
            return "同花顺"
        case .jokerBomb:
            return "四王炸"
        }
    }
}

public enum GuanDanAction: Hashable, Sendable {
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

public enum GuanDanEventKind: String, Codable, Sendable {
    case play
    case pass
    case finish
    case system
}

public struct GuanDanPlayRecord: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let combination: GuanDanCombination?
    public let kind: GuanDanEventKind
    public let message: String

    public init(
        playerIndex: Int,
        playerName: String,
        combination: GuanDanCombination?,
        kind: GuanDanEventKind,
        message: String
    ) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.combination = combination
        self.kind = kind
        self.message = message
    }
}

public struct GuanDanScoreLine: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let team: GuanDanTeam
    public let remainingCards: Int
    public let delta: Int

    public init(playerIndex: Int, playerName: String, team: GuanDanTeam, remainingCards: Int, delta: Int) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.team = team
        self.remainingCards = remainingCards
        self.delta = delta
    }
}

public struct GuanDanState: Hashable, Codable, Sendable {
    public var players: [GuanDanPlayer]
    public var hands: [[Card]]
    public var levelRank: Rank
    public var phase: GuanDanPhase
    public var currentPlayerIndex: Int
    public var lastPlay: GuanDanPlayRecord?
    public var visibleRecord: GuanDanPlayRecord?
    public var tableRecords: [GuanDanPlayRecord?]
    public var passCount: Int
    public var playActionCounts: [Int]
    public var finishedPlayers: [Int]
    public var winnerTeam: GuanDanTeam?
    public var scores: [GuanDanScoreLine]
    public var eventLog: [GuanDanPlayRecord]

    public var isGameOver: Bool {
        phase == .gameOver
    }

    public init(
        players: [GuanDanPlayer],
        hands: [[Card]],
        levelRank: Rank = .two,
        phase: GuanDanPhase = .playing,
        currentPlayerIndex: Int = 0,
        lastPlay: GuanDanPlayRecord? = nil,
        visibleRecord: GuanDanPlayRecord? = nil,
        tableRecords: [GuanDanPlayRecord?]? = nil,
        passCount: Int = 0,
        playActionCounts: [Int]? = nil,
        finishedPlayers: [Int] = [],
        winnerTeam: GuanDanTeam? = nil,
        scores: [GuanDanScoreLine] = [],
        eventLog: [GuanDanPlayRecord] = []
    ) {
        self.players = players
        self.hands = hands.map { $0.sortedForHand() }
        self.levelRank = levelRank
        self.phase = phase
        self.currentPlayerIndex = currentPlayerIndex
        self.lastPlay = lastPlay
        self.visibleRecord = visibleRecord
        self.tableRecords = tableRecords ?? Array(repeating: nil, count: players.count)
        self.passCount = passCount
        self.playActionCounts = playActionCounts ?? Array(repeating: 0, count: players.count)
        self.finishedPlayers = finishedPlayers
        self.winnerTeam = winnerTeam
        self.scores = scores
        self.eventLog = eventLog
    }
}

public enum GuanDanError: Error, Equatable, Sendable {
    case gameOver
    case notPlayersTurn
    case playerAlreadyFinished
    case illegalAction
    case cardsNotInHand
    case invalidCombination
    case cannotBeatPrevious
    case cannotPassOnLead
}

public enum GuanDanRulesEngine {
    public static func classify(_ cards: [Card], levelRank: Rank = .two) -> GuanDanCombination? {
        let cards = cards.sortedForHand()
        guard !cards.isEmpty else { return nil }

        if let jokerBomb = classifyJokerBomb(cards, levelRank: levelRank) {
            return jokerBomb
        }
        if let straightFlush = classifyStraightFlush(cards, levelRank: levelRank) {
            return straightFlush
        }
        if let bomb = classifyBomb(cards, levelRank: levelRank) {
            return bomb
        }
        if let trioWithPair = classifyTrioWithPair(cards, levelRank: levelRank) {
            return trioWithPair
        }
        if let steelPlate = classifySteelPlate(cards, levelRank: levelRank) {
            return steelPlate
        }
        if let pairStraight = classifyPairStraight(cards, levelRank: levelRank) {
            return pairStraight
        }
        if let straight = classifySingleStraight(cards, levelRank: levelRank) {
            return straight
        }
        if let sameRank = classifySameRank(cards, levelRank: levelRank) {
            return sameRank
        }
        return nil
    }

    public static func canBeat(
        _ challenger: GuanDanCombination,
        _ previous: GuanDanCombination,
        levelRank: Rank = .two
    ) -> Bool {
        let challengerPower = bombPower(challenger, levelRank: levelRank)
        let previousPower = bombPower(previous, levelRank: levelRank)
        if challengerPower != previousPower {
            return challengerPower > previousPower
        }
        if challengerPower > 0 {
            if challenger.kind == .bomb && previous.kind == .bomb && challenger.bombCount != previous.bombCount {
                return challenger.bombCount > previous.bombCount
            }
            return rankPower(challenger.primaryRank, levelRank: levelRank) >
                rankPower(previous.primaryRank, levelRank: levelRank)
        }

        guard challenger.kind == previous.kind else { return false }
        guard challenger.cards.count == previous.cards.count else { return false }
        guard challenger.sequenceLength == previous.sequenceLength else { return false }
        return rankPower(challenger.primaryRank, levelRank: levelRank) >
            rankPower(previous.primaryRank, levelRank: levelRank)
    }

    public static func legalCombinations(
        in hand: [Card],
        beating previous: GuanDanCombination? = nil,
        levelRank: Rank = .two
    ) -> [GuanDanCombination] {
        let all = allCombinations(in: hand, levelRank: levelRank)
        let filtered = previous.map { previous in
            all.filter { canBeat($0, previous, levelRank: levelRank) }
        } ?? all
        return filtered.sortedForGuanDanDecision(levelRank: levelRank)
    }

    public static func team(for playerIndex: Int) -> GuanDanTeam {
        playerIndex.isMultiple(of: 2) ? .teamA : .teamB
    }
}

private extension GuanDanRulesEngine {
    static let naturalRanks: [Rank] = Rank.allCases.filter { $0 != .smallJoker && $0 != .bigJoker }
    static let straightRanks: [Rank] = Rank.runRanks

    static func classifyJokerBomb(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count == 4,
              cards.count(of: .smallJoker) == 2,
              cards.count(of: .bigJoker) == 2
        else { return nil }
        return GuanDanCombination(
            kind: .jokerBomb,
            cards: cards,
            primaryRank: .bigJoker,
            bombCount: 4,
            usesWildCards: false
        )
    }

    static func classifyBomb(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count >= 4 else { return nil }
        let split = splitWilds(cards, levelRank: levelRank)
        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        let ranks = Set(split.naturals.map(\.rank))
        guard ranks.count <= 1, let rank = ranks.first ?? naturalRanks.first else { return nil }
        return GuanDanCombination(
            kind: .bomb,
            cards: cards,
            primaryRank: rank,
            bombCount: cards.count,
            usesWildCards: !split.wilds.isEmpty
        )
    }

    static func classifyStraightFlush(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count == 5 else { return nil }
        let split = splitWilds(cards, levelRank: levelRank)
        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        let suits = Set(split.naturals.compactMap(\.suit))
        guard suits.count <= 1 else { return nil }
        guard let rank = straightPrimaryRank(for: split.naturals, wildCount: split.wilds.count) else { return nil }
        return GuanDanCombination(
            kind: .straightFlush,
            cards: cards,
            primaryRank: rank,
            sequenceLength: 5,
            usesWildCards: !split.wilds.isEmpty
        )
    }

    static func classifySingleStraight(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count == 5 else { return nil }
        let split = splitWilds(cards, levelRank: levelRank)
        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        guard let rank = straightPrimaryRank(for: split.naturals, wildCount: split.wilds.count) else { return nil }
        return GuanDanCombination(
            kind: .singleStraight,
            cards: cards,
            primaryRank: rank,
            sequenceLength: 5,
            usesWildCards: !split.wilds.isEmpty
        )
    }

    static func classifyPairStraight(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count == 6 else { return nil }
        let split = splitWilds(cards, levelRank: levelRank)
        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        let counts = rankCounts(split.naturals)
        for window in straightRanks.windows(ofCount: 3) {
            guard counts.keys.allSatisfy({ window.contains($0) }) else { continue }
            let missing = window.reduce(0) { partial, rank in
                partial + max(0, 2 - (counts[rank] ?? 0))
            }
            if missing <= split.wilds.count, counts.values.allSatisfy({ $0 <= 2 }) {
                return GuanDanCombination(
                    kind: .pairStraight,
                    cards: cards,
                    primaryRank: window.last ?? .three,
                    sequenceLength: 3,
                    usesWildCards: !split.wilds.isEmpty
                )
            }
        }
        return nil
    }

    static func classifySteelPlate(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count == 6 else { return nil }
        let split = splitWilds(cards, levelRank: levelRank)
        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        let counts = rankCounts(split.naturals)
        for window in straightRanks.windows(ofCount: 2) {
            guard counts.keys.allSatisfy({ window.contains($0) }) else { continue }
            let missing = window.reduce(0) { partial, rank in
                partial + max(0, 3 - (counts[rank] ?? 0))
            }
            if missing <= split.wilds.count, counts.values.allSatisfy({ $0 <= 3 }) {
                return GuanDanCombination(
                    kind: .steelPlate,
                    cards: cards,
                    primaryRank: window.last ?? .three,
                    sequenceLength: 2,
                    usesWildCards: !split.wilds.isEmpty
                )
            }
        }
        return nil
    }

    static func classifyTrioWithPair(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        guard cards.count == 5 else { return nil }
        let split = splitWilds(cards, levelRank: levelRank)
        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        let counts = rankCounts(split.naturals)
        for trioRank in naturalRanks {
            for pairRank in naturalRanks where pairRank != trioRank {
                guard counts.keys.allSatisfy({ $0 == trioRank || $0 == pairRank }) else { continue }
                guard (counts[trioRank] ?? 0) <= 3, (counts[pairRank] ?? 0) <= 2 else { continue }
                let missing = max(0, 3 - (counts[trioRank] ?? 0)) + max(0, 2 - (counts[pairRank] ?? 0))
                if missing == split.wilds.count {
                    return GuanDanCombination(
                        kind: .trioWithPair,
                        cards: cards,
                        primaryRank: trioRank,
                        usesWildCards: !split.wilds.isEmpty
                    )
                }
            }
        }
        return nil
    }

    static func classifySameRank(_ cards: [Card], levelRank: Rank) -> GuanDanCombination? {
        let split = splitWilds(cards, levelRank: levelRank)
        if cards.count == 1 {
            return GuanDanCombination(
                kind: .single,
                cards: cards,
                primaryRank: split.wilds.isEmpty ? cards[0].rank : levelRank,
                usesWildCards: !split.wilds.isEmpty
            )
        }

        if split.naturals.allSatisfy({ $0.rank == .smallJoker }) || split.naturals.allSatisfy({ $0.rank == .bigJoker }) {
            guard split.wilds.isEmpty, let rank = split.naturals.first?.rank else { return nil }
            if cards.count == 2 {
                return GuanDanCombination(kind: .pair, cards: cards, primaryRank: rank)
            }
            return nil
        }

        guard split.naturals.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else { return nil }
        let ranks = Set(split.naturals.map(\.rank))
        guard ranks.count <= 1 else { return nil }
        let rank = ranks.first ?? levelRank
        switch cards.count {
        case 2:
            return GuanDanCombination(kind: .pair, cards: cards, primaryRank: rank, usesWildCards: !split.wilds.isEmpty)
        case 3:
            return GuanDanCombination(kind: .trio, cards: cards, primaryRank: rank, usesWildCards: !split.wilds.isEmpty)
        default:
            return nil
        }
    }

    static func allCombinations(in hand: [Card], levelRank: Rank) -> [GuanDanCombination] {
        let hand = hand.sortedForHand()
        let split = splitWilds(hand, levelRank: levelRank)
        let wilds = split.wilds.sortedForHand()
        let groups = Dictionary(grouping: split.naturals, by: \.rank).mapValues { $0.sortedForHand() }
        var combinations: [GuanDanCombination] = []

        for card in hand {
            if let single = classify([card], levelRank: levelRank) {
                combinations.append(single)
            }
        }

        if let jokerBomb = classifyJokerBomb(hand.filter { $0.rank == .smallJoker || $0.rank == .bigJoker }, levelRank: levelRank) {
            combinations.append(jokerBomb)
        }

        for rank in naturalRanks {
            let maxCount = min(8, (groups[rank]?.count ?? 0) + wilds.count)
            guard maxCount >= 2 else { continue }
            for count in 2...maxCount {
                guard let cards = takeCards(rank: rank, count: count, groups: groups, wilds: wilds),
                      let combination = classify(cards, levelRank: levelRank)
                else { continue }
                combinations.append(combination)
            }
        }

        for rank in [Rank.smallJoker, .bigJoker] {
            if let cards = groups[rank], cards.count >= 2,
               let pair = classify(Array(cards.prefix(2)), levelRank: levelRank) {
                combinations.append(pair)
            }
        }

        combinations.append(contentsOf: straightCombinations(groups: groups, wilds: wilds, levelRank: levelRank))
        combinations.append(contentsOf: pairStraightCombinations(groups: groups, wilds: wilds, levelRank: levelRank))
        combinations.append(contentsOf: steelPlateCombinations(groups: groups, wilds: wilds, levelRank: levelRank))
        combinations.append(contentsOf: trioWithPairCombinations(groups: groups, wilds: wilds, levelRank: levelRank))

        var seen = Set<String>()
        return combinations.filter { combination in
            let signature = "\(combination.kind.rawValue):" + combination.cards.map(\.id).joined(separator: ",")
            if seen.contains(signature) {
                return false
            }
            seen.insert(signature)
            return true
        }
    }

    static func straightCombinations(
        groups: [Rank: [Card]],
        wilds: [Card],
        levelRank: Rank
    ) -> [GuanDanCombination] {
        var combinations: [GuanDanCombination] = []
        for window in straightRanks.windows(ofCount: 5) {
            if let cards = takeRunCards(ranks: window, repeatCount: 1, groups: groups, wilds: wilds),
               let straight = classify(cards, levelRank: levelRank) {
                combinations.append(straight)
            }

            for suit in Suit.allCases {
                if let cards = takeRunCards(ranks: window, repeatCount: 1, groups: groups, wilds: wilds, suit: suit),
                   let straightFlush = classify(cards, levelRank: levelRank) {
                    combinations.append(straightFlush)
                }
            }
        }
        return combinations
    }

    static func pairStraightCombinations(
        groups: [Rank: [Card]],
        wilds: [Card],
        levelRank: Rank
    ) -> [GuanDanCombination] {
        straightRanks.windows(ofCount: 3).compactMap { window in
            guard let cards = takeRunCards(ranks: window, repeatCount: 2, groups: groups, wilds: wilds) else { return nil }
            return classify(cards, levelRank: levelRank)
        }
    }

    static func steelPlateCombinations(
        groups: [Rank: [Card]],
        wilds: [Card],
        levelRank: Rank
    ) -> [GuanDanCombination] {
        straightRanks.windows(ofCount: 2).compactMap { window in
            guard let cards = takeRunCards(ranks: window, repeatCount: 3, groups: groups, wilds: wilds) else { return nil }
            return classify(cards, levelRank: levelRank)
        }
    }

    static func trioWithPairCombinations(
        groups: [Rank: [Card]],
        wilds: [Card],
        levelRank: Rank
    ) -> [GuanDanCombination] {
        var combinations: [GuanDanCombination] = []
        for trioRank in naturalRanks {
            for pairRank in naturalRanks where pairRank != trioRank {
                var remainingWilds = wilds
                guard let trio = takeCards(rank: trioRank, count: 3, groups: groups, wilds: remainingWilds) else { continue }
                remainingWilds.removeUsedWilds(in: trio, levelRank: levelRank)
                guard let pair = takeCards(rank: pairRank, count: 2, groups: groups, wilds: remainingWilds),
                      let combo = classify(trio + pair, levelRank: levelRank)
                else { continue }
                combinations.append(combo)
            }
        }
        return combinations
    }

    static func takeCards(
        rank: Rank,
        count: Int,
        groups: [Rank: [Card]],
        wilds: [Card]
    ) -> [Card]? {
        let natural = Array((groups[rank] ?? []).prefix(count))
        let missing = count - natural.count
        guard missing >= 0, missing <= wilds.count else { return nil }
        return natural + Array(wilds.prefix(missing))
    }

    static func takeRunCards(
        ranks: [Rank],
        repeatCount: Int,
        groups: [Rank: [Card]],
        wilds: [Card],
        suit: Suit? = nil
    ) -> [Card]? {
        var cards: [Card] = []
        var remainingWilds = wilds
        for rank in ranks {
            let candidates = (groups[rank] ?? []).filter { card in
                suit.map { card.suit == $0 } ?? true
            }
            cards.append(contentsOf: candidates.prefix(repeatCount))
            let missing = repeatCount - min(repeatCount, candidates.count)
            guard missing <= remainingWilds.count else { return nil }
            cards.append(contentsOf: remainingWilds.prefix(missing))
            remainingWilds.removeFirst(missing)
        }
        return cards
    }

    static func straightPrimaryRank(for naturals: [Card], wildCount: Int) -> Rank? {
        guard naturals.allSatisfy({ $0.rank.canBeInRun }) else { return nil }
        let naturalRanks = naturals.map(\.rank)
        guard Set(naturalRanks).count == naturalRanks.count else { return nil }
        for window in straightRanks.windows(ofCount: 5).reversed() {
            guard naturalRanks.allSatisfy({ window.contains($0) }) else { continue }
            if 5 - naturalRanks.count <= wildCount {
                return window.last
            }
        }
        return nil
    }

    static func splitWilds(_ cards: [Card], levelRank: Rank) -> (wilds: [Card], naturals: [Card]) {
        let wilds = cards.filter { isWild($0, levelRank: levelRank) }
        let naturals = cards.filter { !isWild($0, levelRank: levelRank) }
        return (wilds, naturals)
    }

    static func isWild(_ card: Card, levelRank: Rank) -> Bool {
        card.rank == levelRank && card.suit == .hearts
    }

    static func rankCounts(_ cards: [Card]) -> [Rank: Int] {
        Dictionary(grouping: cards, by: \.rank).mapValues(\.count)
    }

    static func rankPower(_ rank: Rank, levelRank: Rank) -> Int {
        switch rank {
        case .bigJoker:
            return 1_000
        case .smallJoker:
            return 990
        default:
            return rank == levelRank ? 900 : rank.rawValue
        }
    }

    static func bombPower(_ combination: GuanDanCombination, levelRank: Rank) -> Int {
        switch combination.kind {
        case .jokerBomb:
            return 10_000
        case .bomb where combination.bombCount >= 6:
            return 7_000 + combination.bombCount * 100 + rankPower(combination.primaryRank, levelRank: levelRank)
        case .straightFlush:
            return 6_500 + rankPower(combination.primaryRank, levelRank: levelRank)
        case .bomb where combination.bombCount == 5:
            return 6_000 + rankPower(combination.primaryRank, levelRank: levelRank)
        case .bomb:
            return 5_000 + rankPower(combination.primaryRank, levelRank: levelRank)
        default:
            return 0
        }
    }
}

public final class GuanDanGameEngine {
    public private(set) var state: GuanDanState

    public convenience init() {
        var deck = DeckConfig(deckCount: 2).makeDeck()
        deck.shuffle()
        self.init(deck: deck)
    }

    public init(deck: [Card], startingPlayer: Int? = nil, levelRank: Rank = .two) {
        let players = [
            GuanDanPlayer(name: "你", isHuman: true),
            GuanDanPlayer(name: "AI 左", isHuman: false),
            GuanDanPlayer(name: "AI 上", isHuman: false),
            GuanDanPlayer(name: "AI 右", isHuman: false)
        ]
        let hands = Self.deal(deck: deck)
        let first = startingPlayer ?? Self.findHeartThreeHolder(in: hands) ?? 0
        self.state = GuanDanState(players: players, hands: hands, levelRank: levelRank, currentPlayerIndex: first)
        appendSystemEvent("固定打2，红桃2为逢人配")
    }

    public init(players: [GuanDanPlayer], hands: [[Card]], startingPlayer: Int, levelRank: Rank = .two) {
        self.state = GuanDanState(players: players, hands: hands, levelRank: levelRank, currentPlayerIndex: startingPlayer)
    }

    public init(state: GuanDanState) {
        self.state = state
    }

    public static func deal(deck: [Card]) -> [[Card]] {
        let playable = Array(deck.prefix(108))
        var hands = Array(repeating: [Card](), count: 4)
        for (index, card) in playable.enumerated() {
            hands[index % 4].append(card)
        }
        return hands.map { $0.sortedForHand() }
    }

    public static func findHeartThreeHolder(in hands: [[Card]]) -> Int? {
        hands.firstIndex { hand in
            hand.contains { $0.rank == .three && $0.suit == .hearts }
        }
    }

    public func legalActions(for playerIndex: Int) -> [GuanDanAction] {
        guard state.phase == .playing,
              state.currentPlayerIndex == playerIndex,
              !state.finishedPlayers.contains(playerIndex)
        else { return [] }
        let previous = activePreviousCombination(for: playerIndex)
        let plays = GuanDanRulesEngine.legalCombinations(
            in: state.hands[playerIndex],
            beating: previous,
            levelRank: state.levelRank
        ).map { GuanDanAction.play($0.cards) }
        if previous == nil {
            return plays
        }
        return plays + [.pass]
    }

    public func apply(_ action: GuanDanAction) throws {
        guard state.phase == .playing else { throw GuanDanError.gameOver }
        let playerIndex = state.currentPlayerIndex
        guard !state.finishedPlayers.contains(playerIndex) else { throw GuanDanError.playerAlreadyFinished }
        switch action {
        case .pass:
            try pass(playerIndex)
        case .play(let cards):
            try play(cards, by: playerIndex)
        }
    }
}

private extension GuanDanGameEngine {
    func activePreviousCombination(for playerIndex: Int) -> GuanDanCombination? {
        guard let lastPlay = state.lastPlay,
              lastPlay.playerIndex != playerIndex
        else { return nil }
        return lastPlay.combination
    }

    func play(_ cards: [Card], by playerIndex: Int) throws {
        guard Set(cards).isSubset(of: Set(state.hands[playerIndex])) else {
            throw GuanDanError.cardsNotInHand
        }
        guard let combination = GuanDanRulesEngine.classify(cards, levelRank: state.levelRank) else {
            throw GuanDanError.invalidCombination
        }
        if let previous = activePreviousCombination(for: playerIndex),
           !GuanDanRulesEngine.canBeat(combination, previous, levelRank: state.levelRank) {
            throw GuanDanError.cannotBeatPrevious
        }

        state.hands[playerIndex] = state.hands[playerIndex].removing(cards).sortedForHand()
        state.playActionCounts[playerIndex] += 1
        state.passCount = 0

        let record = GuanDanPlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: combination,
            kind: .play,
            message: "\(state.players[playerIndex].name)出\(combination.displayName)"
        )
        state.lastPlay = record
        state.visibleRecord = record
        setTableRecord(record)
        state.eventLog.append(record)

        if state.hands[playerIndex].isEmpty {
            finishPlayer(playerIndex)
            if state.isGameOver { return }
        }

        state.currentPlayerIndex = nextActivePlayer(after: playerIndex)
    }

    func pass(_ playerIndex: Int) throws {
        guard activePreviousCombination(for: playerIndex) != nil else {
            throw GuanDanError.cannotPassOnLead
        }

        let record = GuanDanPlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: nil,
            kind: .pass,
            message: "\(state.players[playerIndex].name)过"
        )
        setTableRecord(record)
        state.visibleRecord = record
        state.eventLog.append(record)
        state.passCount += 1

        let activeCount = activePlayers.count
        if state.passCount >= max(1, activeCount - 1), let controller = state.lastPlay?.playerIndex {
            state.lastPlay = nil
            state.passCount = 0
            clearTableRecords(keeping: controller)
            let lead = leadAfterPassRound(controller: controller)
            state.currentPlayerIndex = lead
            appendSystemEvent("\(state.players[lead].name)接牌")
        } else {
            state.currentPlayerIndex = nextActivePlayer(after: playerIndex)
        }
    }

    func finishPlayer(_ playerIndex: Int) {
        if !state.finishedPlayers.contains(playerIndex) {
            state.finishedPlayers.append(playerIndex)
        }
        let record = GuanDanPlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: nil,
            kind: .finish,
            message: "\(state.players[playerIndex].name)出完"
        )
        state.eventLog.append(record)

        let team = GuanDanRulesEngine.team(for: playerIndex)
        let teammate = (playerIndex + 2) % state.players.count
        if state.finishedPlayers.contains(teammate) || activePlayers.count <= 1 {
            finishGame(winningTeam: team)
        }
    }

    func finishGame(winningTeam: GuanDanTeam) {
        state.phase = .gameOver
        state.winnerTeam = winningTeam
        let losingRemainder = state.players.indices
            .filter { GuanDanRulesEngine.team(for: $0) != winningTeam }
            .map { state.hands[$0].count }
            .reduce(0, +)
        state.scores = state.players.indices.map { index in
            let team = GuanDanRulesEngine.team(for: index)
            let remaining = state.hands[index].count
            return GuanDanScoreLine(
                playerIndex: index,
                playerName: state.players[index].name,
                team: team,
                remainingCards: remaining,
                delta: team == winningTeam ? losingRemainder : -remaining
            )
        }
        appendSystemEvent(winningTeam == .teamA ? "你方胜利" : "对方胜利")
    }

    var activePlayers: [Int] {
        state.players.indices.filter { !state.finishedPlayers.contains($0) }
    }

    func leadAfterPassRound(controller: Int) -> Int {
        if !state.finishedPlayers.contains(controller) {
            return controller
        }
        let teammate = (controller + 2) % state.players.count
        if !state.finishedPlayers.contains(teammate) {
            return teammate
        }
        return nextActivePlayer(after: controller)
    }

    func nextActivePlayer(after playerIndex: Int) -> Int {
        var next = (playerIndex + 1) % state.players.count
        while state.finishedPlayers.contains(next) {
            next = (next + 1) % state.players.count
        }
        return next
    }

    func setTableRecord(_ record: GuanDanPlayRecord) {
        guard state.tableRecords.indices.contains(record.playerIndex) else { return }
        state.tableRecords[record.playerIndex] = record
    }

    func clearTableRecords(keeping playerIndex: Int? = nil) {
        for index in state.tableRecords.indices where index != playerIndex {
            state.tableRecords[index] = nil
        }
    }

    func appendSystemEvent(_ message: String) {
        let record = GuanDanPlayRecord(
            playerIndex: state.currentPlayerIndex,
            playerName: "系统",
            combination: nil,
            kind: .system,
            message: message
        )
        state.visibleRecord = record
        state.eventLog.append(record)
    }
}

public struct GuanDanAIPlayer: Sendable {
    public init() {}

    public func chooseAction(state: GuanDanState, for playerIndex: Int) -> GuanDanAction {
        let actions = GuanDanGameEngine(state: state).legalActions(for: playerIndex)
        guard !actions.isEmpty else { return .pass }
        if let finishing = actions.first(where: { !$0.cards.isEmpty && $0.cards.count == state.hands[playerIndex].count }) {
            return finishing
        }
        return actions.max {
            score($0, state: state, playerIndex: playerIndex) < score($1, state: state, playerIndex: playerIndex)
        } ?? actions[0]
    }

    public func legalActions(from state: GuanDanState, for playerIndex: Int) -> [GuanDanAction] {
        GuanDanGameEngine(state: state).legalActions(for: playerIndex)
    }

    private func score(_ action: GuanDanAction, state: GuanDanState, playerIndex: Int) -> Int {
        guard !action.cards.isEmpty else {
            return passScore(state: state, playerIndex: playerIndex)
        }
        guard let combination = GuanDanRulesEngine.classify(action.cards, levelRank: state.levelRank) else {
            return -100_000
        }
        let hand = state.hands[playerIndex]
        let remaining = hand.removing(action.cards)
        let before = turnEstimate(hand, levelRank: state.levelRank)
        let after = turnEstimate(remaining, levelRank: state.levelRank)
        let pressure = tablePressure(state: state, playerIndex: playerIndex)
        let teammate = (playerIndex + 2) % state.players.count
        let lastByTeammate = state.lastPlay?.playerIndex == teammate
        let canFinish = remaining.isEmpty

        var value = (before - after) * 700 + action.cards.count * 34
        value -= GuanDanRulesEngine.comparisonRankValue(combination.primaryRank, levelRank: state.levelRank) * 8

        switch combination.kind {
        case .singleStraight:
            value += 620
        case .pairStraight:
            value += 780
        case .steelPlate:
            value += 860
        case .trioWithPair:
            value += hand.count <= 8 ? 420 : 120
        case .bomb:
            value -= max(360, 1_900 - pressure * 18 - combination.bombCount * 120)
        case .straightFlush:
            value -= max(420, 1_650 - pressure * 16)
        case .jokerBomb:
            value -= max(900, 2_700 - pressure * 18)
        case .single:
            if opponentMinimumCards(state: state, playerIndex: playerIndex) == 1 { value -= 540 }
        case .pair, .trio:
            value += 120
        }

        if lastByTeammate && !canFinish {
            value -= 5_200
            if opponentMinimumCards(state: state, playerIndex: playerIndex) <= 3 {
                value += 1_200
            }
        }
        if state.lastPlay?.playerIndex != nil && state.lastPlay?.playerIndex != playerIndex {
            value += pressure * 7
        }
        if remaining.count <= 5 {
            value += 520
        }
        if opponentMinimumCards(state: state, playerIndex: playerIndex) <= 2 && blocksShortOpponent(combination) {
            value += 760 + pressure * 7
        }
        return value
    }

    private func passScore(state: GuanDanState, playerIndex: Int) -> Int {
        let teammate = (playerIndex + 2) % state.players.count
        if state.lastPlay?.playerIndex == teammate {
            return 1_200
        }
        return -tablePressure(state: state, playerIndex: playerIndex) * 10
    }

    private func tablePressure(state: GuanDanState, playerIndex: Int) -> Int {
        let minOpponent = opponentMinimumCards(state: state, playerIndex: playerIndex)
        let played = state.playActionCounts.reduce(0, +)
        return min(100, max(0, 72 - minOpponent * 7) + played * 2 + state.passCount * 4)
    }

    private func opponentMinimumCards(state: GuanDanState, playerIndex: Int) -> Int {
        let ownTeam = GuanDanRulesEngine.team(for: playerIndex)
        return state.hands.indices
            .filter { GuanDanRulesEngine.team(for: $0) != ownTeam && !state.finishedPlayers.contains($0) }
            .map { state.hands[$0].count }
            .min() ?? 27
    }

    private func turnEstimate(_ cards: [Card], levelRank: Rank) -> Int {
        guard !cards.isEmpty else { return 0 }
        if GuanDanRulesEngine.classify(cards, levelRank: levelRank) != nil { return 1 }

        var counts = Dictionary(grouping: cards, by: \.rank).mapValues(\.count)
        counts[.smallJoker] = nil
        counts[.bigJoker] = nil
        var turns = 0

        while consumeRun(from: &counts, repeatCount: 2, length: 3) {
            turns += 1
        }
        while consumeRun(from: &counts, repeatCount: 3, length: 2) {
            turns += 1
        }
        while consumeRun(from: &counts, repeatCount: 1, length: 5) {
            turns += 1
        }

        for rank in Rank.allCases where rank != .smallJoker && rank != .bigJoker {
            var count = counts[rank] ?? 0
            while count >= 5 {
                turns += 1
                count -= 5
            }
            if count >= 4 {
                turns += 1
                count = 0
            }
            if count == 3 {
                turns += 1
                count = 0
            }
            if count == 2 {
                turns += 1
                count = 0
            }
            if count == 1 {
                turns += 1
            }
        }

        let jokerCount = cards.filter { $0.rank == .smallJoker || $0.rank == .bigJoker }.count
        if jokerCount == 4 {
            turns += 1
        } else {
            turns += Int(ceil(Double(jokerCount) / 2.0))
        }
        return max(1, turns)
    }

    private func planningScore(_ combination: GuanDanCombination, levelRank: Rank) -> Int {
        var score = combination.cards.count * 260 -
            GuanDanRulesEngine.comparisonRankValue(combination.primaryRank, levelRank: levelRank) * 5
        switch combination.kind {
        case .singleStraight:
            score += 620
        case .pairStraight:
            score += 760
        case .steelPlate:
            score += 820
        case .trioWithPair:
            score += 360
        case .bomb:
            score += 160 + combination.bombCount * 35
        case .straightFlush:
            score += 260
        case .jokerBomb:
            score -= 180
        case .single, .pair, .trio:
            break
        }
        return score
    }

    private func consumeRun(from counts: inout [Rank: Int], repeatCount: Int, length: Int) -> Bool {
        let ranks = Rank.runRanks
        var bestStart: Int?
        var bestEnd: Int?
        var currentStart: Int?

        for index in ranks.indices {
            if (counts[ranks[index]] ?? 0) >= repeatCount {
                if currentStart == nil {
                    currentStart = index
                }
                if let start = currentStart, index - start + 1 >= length {
                    let bestLength = bestStart.flatMap { start in bestEnd.map { $0 - start + 1 } } ?? 0
                    if index - start + 1 > bestLength {
                        bestStart = start
                        bestEnd = index
                    }
                }
            } else {
                currentStart = nil
            }
        }

        guard let bestStart, let bestEnd else { return false }
        for rank in ranks[bestStart...bestEnd] {
            counts[rank] = (counts[rank] ?? 0) - repeatCount
        }
        return true
    }

    private func blocksShortOpponent(_ combination: GuanDanCombination) -> Bool {
        switch combination.kind {
        case .single:
            return false
        case .pair, .trio, .trioWithPair, .singleStraight, .pairStraight, .steelPlate, .bomb, .straightFlush, .jokerBomb:
            return true
        }
    }
}

public enum GuanDanHintEngine {
    public static func bestAction(state: GuanDanState, for playerIndex: Int) -> GuanDanAction? {
        let action = GuanDanAIPlayer().chooseAction(state: state, for: playerIndex)
        return action.cards.isEmpty ? nil : action
    }
}

private extension GuanDanRulesEngine {
    static func comparisonRankValue(_ rank: Rank, levelRank: Rank) -> Int {
        rankPower(rank, levelRank: levelRank)
    }
}

private extension Array where Element == GuanDanCombination {
    func sortedForGuanDanDecision(levelRank: Rank) -> [GuanDanCombination] {
        sorted {
            let lhsBomb = $0.isBombLike
            let rhsBomb = $1.isBombLike
            if lhsBomb != rhsBomb {
                return !lhsBomb
            }
            let lhsScore = GuanDanRulesEngine.comparisonRankValue($0.primaryRank, levelRank: levelRank) + $0.cards.count * 20
            let rhsScore = GuanDanRulesEngine.comparisonRankValue($1.primaryRank, levelRank: levelRank) + $1.cards.count * 20
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return $0.cards.count < $1.cards.count
        }
    }
}

private extension Array where Element == Rank {
    func windows(ofCount count: Int) -> [[Rank]] {
        guard count > 0, self.count >= count else { return [] }
        return indices.dropLast(count - 1).map { start in
            Array(self[start..<(start + count)])
        }
    }
}

private extension Array where Element == Card {
    func removing(_ cards: [Card]) -> [Card] {
        var remaining = self
        for card in cards {
            if let index = remaining.firstIndex(of: card) {
                remaining.remove(at: index)
            }
        }
        return remaining
    }

    mutating func removeUsedWilds(in cards: [Card], levelRank: Rank) {
        for card in cards where card.rank == levelRank && card.suit == .hearts {
            if let index = firstIndex(of: card) {
                remove(at: index)
            }
        }
    }
}
