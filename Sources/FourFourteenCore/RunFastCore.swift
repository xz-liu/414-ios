import Foundation

public struct RunFastPlayer: Hashable, Codable, Sendable {
    public let name: String
    public let isHuman: Bool

    public init(name: String, isHuman: Bool) {
        self.name = name
        self.isHuman = isHuman
    }
}

public enum RunFastPhase: String, Codable, Sendable {
    case playing
    case gameOver
}

public enum RunFastCombinationKind: String, Codable, Sendable {
    case single
    case pair
    case trio
    case trioWithTwo
    case singleStraight
    case pairStraight
    case airplane
    case airplaneWithWings
    case bomb
}

public struct RunFastCombination: Hashable, Codable, Sendable {
    public let kind: RunFastCombinationKind
    public let cards: [Card]
    public let primaryRank: Rank
    public let sequenceLength: Int

    public init(
        kind: RunFastCombinationKind,
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
        kind == .bomb
    }

    public var displayName: String {
        switch kind {
        case .single:
            return "单张"
        case .pair:
            return "对子"
        case .trio:
            return "三张"
        case .trioWithTwo:
            return "三带二"
        case .singleStraight:
            return "顺子"
        case .pairStraight:
            return "连对"
        case .airplane:
            return "飞机"
        case .airplaneWithWings:
            return "飞机带翅膀"
        case .bomb:
            return "炸弹"
        }
    }
}

public enum RunFastAction: Hashable, Sendable {
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

public enum RunFastEventKind: String, Codable, Sendable {
    case play
    case pass
    case system
}

public struct RunFastPlayRecord: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let combination: RunFastCombination?
    public let kind: RunFastEventKind
    public let message: String

    public init(
        playerIndex: Int,
        playerName: String,
        combination: RunFastCombination?,
        kind: RunFastEventKind,
        message: String
    ) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.combination = combination
        self.kind = kind
        self.message = message
    }
}

public struct RunFastScoreLine: Hashable, Codable, Sendable {
    public let playerIndex: Int
    public let playerName: String
    public let remainingCards: Int
    public let delta: Int

    public init(playerIndex: Int, playerName: String, remainingCards: Int, delta: Int) {
        self.playerIndex = playerIndex
        self.playerName = playerName
        self.remainingCards = remainingCards
        self.delta = delta
    }
}

public struct RunFastState: Hashable, Codable, Sendable {
    public var players: [RunFastPlayer]
    public var hands: [[Card]]
    public var phase: RunFastPhase
    public var currentPlayerIndex: Int
    public var lastPlay: RunFastPlayRecord?
    public var visibleRecord: RunFastPlayRecord?
    public var tableRecords: [RunFastPlayRecord?]
    public var passCount: Int
    public var playActionCounts: [Int]
    public var winnerIndex: Int?
    public var scores: [RunFastScoreLine]
    public var eventLog: [RunFastPlayRecord]

    public var isGameOver: Bool {
        phase == .gameOver
    }

    public init(
        players: [RunFastPlayer],
        hands: [[Card]],
        phase: RunFastPhase = .playing,
        currentPlayerIndex: Int = 0,
        lastPlay: RunFastPlayRecord? = nil,
        visibleRecord: RunFastPlayRecord? = nil,
        tableRecords: [RunFastPlayRecord?]? = nil,
        passCount: Int = 0,
        playActionCounts: [Int]? = nil,
        winnerIndex: Int? = nil,
        scores: [RunFastScoreLine] = [],
        eventLog: [RunFastPlayRecord] = []
    ) {
        self.players = players
        self.hands = hands.map { $0.sortedForHand() }
        self.phase = phase
        self.currentPlayerIndex = currentPlayerIndex
        self.lastPlay = lastPlay
        self.visibleRecord = visibleRecord
        self.tableRecords = tableRecords ?? Array(repeating: nil, count: players.count)
        self.passCount = passCount
        self.playActionCounts = playActionCounts ?? Array(repeating: 0, count: players.count)
        self.winnerIndex = winnerIndex
        self.scores = scores
        self.eventLog = eventLog
    }
}

public enum RunFastError: Error, Equatable, Sendable {
    case gameOver
    case notPlayersTurn
    case illegalAction
    case cardsNotInHand
    case invalidCombination
    case cannotBeatPrevious
    case cannotPassOnLead
    case firstPlayMustContainSpadeThree
}

public enum RunFastRulesEngine {
    public static func classify(_ cards: [Card]) -> RunFastCombination? {
        let cards = cards.sortedForHand()
        guard !cards.isEmpty, cards.allSatisfy({ $0.rank != .smallJoker && $0.rank != .bigJoker }) else {
            return nil
        }

        if let sameRank = classifySameRank(cards) {
            return sameRank
        }
        if let trioWithTwo = classifyTrioWithTwo(cards) {
            return trioWithTwo
        }
        if let straight = classifySingleStraight(cards) {
            return straight
        }
        if let pairStraight = classifyPairStraight(cards) {
            return pairStraight
        }
        if let airplane = classifyAirplane(cards) {
            return airplane
        }
        return nil
    }

    public static func canBeat(_ challenger: RunFastCombination, _ previous: RunFastCombination) -> Bool {
        if challenger.kind == .bomb && previous.kind == .bomb {
            return challenger.primaryRank.rawValue > previous.primaryRank.rawValue
        }
        if challenger.kind == .bomb && previous.kind != .bomb {
            return true
        }
        if previous.kind == .bomb && challenger.kind != .bomb {
            return false
        }
        guard challenger.kind == previous.kind else { return false }
        guard challenger.cards.count == previous.cards.count else { return false }
        guard challenger.sequenceLength == previous.sequenceLength else { return false }
        return challenger.primaryRank.rawValue > previous.primaryRank.rawValue
    }

    public static func legalCombinations(in hand: [Card], beating previous: RunFastCombination? = nil) -> [RunFastCombination] {
        let all = allCombinations(in: hand)
        let filtered = previous.map { previous in
            all.filter { canBeat($0, previous) }
        } ?? all
        return filtered.sortedForRunFastDecision()
    }

    public static func combinationSortScore(_ combination: RunFastCombination) -> Int {
        let rank = combination.primaryRank.rawValue
        switch combination.kind {
        case .single:
            return 100 + rank
        case .pair:
            return 200 + rank
        case .trio:
            return 300 + rank
        case .trioWithTwo:
            return 520 + rank
        case .singleStraight:
            return 900 + combination.sequenceLength * 24 + rank
        case .pairStraight:
            return 1_120 + combination.sequenceLength * 28 + rank
        case .airplane:
            return 1_360 + combination.sequenceLength * 38 + rank
        case .airplaneWithWings:
            return 1_520 + combination.sequenceLength * 42 + rank
        case .bomb:
            return 10_000 + rank
        }
    }
}

private extension RunFastRulesEngine {
    static func classifySameRank(_ cards: [Card]) -> RunFastCombination? {
        guard let rank = cards.first?.rank,
              cards.allSatisfy({ $0.rank == rank })
        else { return nil }

        switch cards.count {
        case 1:
            return RunFastCombination(kind: .single, cards: cards, primaryRank: rank)
        case 2:
            return RunFastCombination(kind: .pair, cards: cards, primaryRank: rank)
        case 3:
            return RunFastCombination(kind: .trio, cards: cards, primaryRank: rank)
        case 4:
            return RunFastCombination(kind: .bomb, cards: cards, primaryRank: rank)
        default:
            return nil
        }
    }

    static func classifyTrioWithTwo(_ cards: [Card]) -> RunFastCombination? {
        guard cards.count == 5 else { return nil }
        let groups = rankGroups(cards)
        guard let trio = groups.first(where: { $0.value.count == 3 }) else { return nil }
        return RunFastCombination(kind: .trioWithTwo, cards: cards, primaryRank: trio.key)
    }

    static func classifySingleStraight(_ cards: [Card]) -> RunFastCombination? {
        guard cards.count >= 5,
              cards.allSatisfy({ $0.rank.canBeInRun })
        else { return nil }
        let ranks = cards.map(\.rank)
        guard Set(ranks).count == ranks.count,
              ranks.sorted().areConsecutive
        else { return nil }
        return RunFastCombination(
            kind: .singleStraight,
            cards: cards,
            primaryRank: ranks.max() ?? .three,
            sequenceLength: ranks.count
        )
    }

    static func classifyPairStraight(_ cards: [Card]) -> RunFastCombination? {
        guard cards.count >= 4, cards.count.isMultiple(of: 2) else { return nil }
        let groups = rankGroups(cards)
        guard groups.count >= 2,
              groups.values.allSatisfy({ $0.count == 2 }),
              groups.keys.allSatisfy(\.canBeInRun)
        else { return nil }
        let ranks = groups.keys.sorted()
        guard ranks.areConsecutive else { return nil }
        return RunFastCombination(
            kind: .pairStraight,
            cards: cards,
            primaryRank: ranks.max() ?? .three,
            sequenceLength: ranks.count
        )
    }

    static func classifyAirplane(_ cards: [Card]) -> RunFastCombination? {
        if let bare = classifyBareAirplane(cards) {
            return bare
        }
        return classifyAirplaneWithWings(cards)
    }

    static func classifyBareAirplane(_ cards: [Card]) -> RunFastCombination? {
        guard cards.count >= 6, cards.count.isMultiple(of: 3) else { return nil }
        let groups = rankGroups(cards)
        guard groups.count >= 2,
              groups.values.allSatisfy({ $0.count == 3 }),
              groups.keys.allSatisfy(\.canBeInRun)
        else { return nil }
        let ranks = groups.keys.sorted()
        guard ranks.areConsecutive else { return nil }
        return RunFastCombination(
            kind: .airplane,
            cards: cards,
            primaryRank: ranks.max() ?? .three,
            sequenceLength: ranks.count
        )
    }

    static func classifyAirplaneWithWings(_ cards: [Card]) -> RunFastCombination? {
        guard cards.count >= 10, cards.count.isMultiple(of: 5) else { return nil }
        let length = cards.count / 5
        guard let trioRanks = consecutiveTrioRanks(in: cards, length: length) else { return nil }
        let wings = cards.removingFirst(count: 3, forEach: trioRanks)
        guard wings.count == length * 2 else { return nil }
        return RunFastCombination(
            kind: .airplaneWithWings,
            cards: cards,
            primaryRank: trioRanks.max() ?? .three,
            sequenceLength: trioRanks.count
        )
    }

    static func allCombinations(in hand: [Card]) -> [RunFastCombination] {
        let hand = hand.sortedForHand().filter { $0.rank != .smallJoker && $0.rank != .bigJoker }
        let groups = rankGroups(hand).mapValues { $0.sortedForHand() }
        var combinations: [RunFastCombination] = []

        for (_, cards) in groups {
            if let single = cards.first.flatMap({ classify([$0]) }) {
                combinations.append(single)
            }
            if cards.count >= 2, let pair = classify(Array(cards.prefix(2))) {
                combinations.append(pair)
            }
            if cards.count >= 3, let trio = classify(Array(cards.prefix(3))) {
                combinations.append(trio)
            }
            if cards.count >= 4, let bomb = classify(Array(cards.prefix(4))) {
                combinations.append(bomb)
            }
        }

        for (rank, cards) in groups where cards.count >= 3 {
            let trio = Array(cards.prefix(3))
            let attachments = hand.filter { $0.rank != rank }
            if attachments.count >= 2,
               let combo = classify(trio + Array(attachments.prefix(2))) {
                combinations.append(combo)
            }
        }

        combinations.append(contentsOf: runCombinations(groups: groups, repeatCount: 1, minimumLength: 5))
        combinations.append(contentsOf: runCombinations(groups: groups, repeatCount: 2, minimumLength: 2))
        combinations.append(contentsOf: airplaneCombinations(groups: groups, hand: hand))

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

    static func runCombinations(
        groups: [Rank: [Card]],
        repeatCount: Int,
        minimumLength: Int
    ) -> [RunFastCombination] {
        let ranks = Rank.runRanks
        var combinations: [RunFastCombination] = []

        for startIndex in ranks.indices {
            var endIndex = startIndex
            while endIndex < ranks.count, (groups[ranks[endIndex]]?.count ?? 0) >= repeatCount {
                let length = endIndex - startIndex + 1
                if length >= minimumLength {
                    let cards = ranks[startIndex...endIndex].flatMap { rank in
                        Array((groups[rank] ?? []).prefix(repeatCount))
                    }
                    if let combo = classify(cards) {
                        combinations.append(combo)
                    }
                }
                endIndex += 1
            }
        }
        return combinations
    }

    static func airplaneCombinations(groups: [Rank: [Card]], hand: [Card]) -> [RunFastCombination] {
        let ranks = Rank.runRanks
        var combinations: [RunFastCombination] = []
        for startIndex in ranks.indices {
            var endIndex = startIndex
            while endIndex < ranks.count, (groups[ranks[endIndex]]?.count ?? 0) >= 3 {
                let length = endIndex - startIndex + 1
                if length >= 2 {
                    let trioRanks = Array(ranks[startIndex...endIndex])
                    let trioCards = trioRanks.flatMap { rank in
                        Array((groups[rank] ?? []).prefix(3))
                    }
                    if let bare = classify(trioCards) {
                        combinations.append(bare)
                    }
                    let attachments = hand.filter { !trioRanks.contains($0.rank) }
                    if attachments.count >= length * 2,
                       let withWings = classify(trioCards + Array(attachments.prefix(length * 2))) {
                        combinations.append(withWings)
                    }
                }
                endIndex += 1
            }
        }
        return combinations
    }

    static func rankGroups(_ cards: [Card]) -> [Rank: [Card]] {
        Dictionary(grouping: cards, by: \.rank)
    }

    static func consecutiveTrioRanks(in cards: [Card], length: Int) -> [Rank]? {
        let groups = rankGroups(cards)
        let candidates = groups
            .filter { $0.value.count >= 3 && $0.key.canBeInRun }
            .map(\.key)
            .sorted()
        guard candidates.count >= length else { return nil }
        for window in candidates.windows(ofCount: length) where window.areConsecutive {
            return Array(window)
        }
        return nil
    }
}

public final class RunFastGameEngine {
    public private(set) var state: RunFastState

    public convenience init() {
        var deck = Self.playableDeck()
        deck.shuffle()
        self.init(deck: deck)
    }

    public init(deck: [Card], startingPlayer: Int? = nil) {
        let players = [
            RunFastPlayer(name: "你", isHuman: true),
            RunFastPlayer(name: "AI 左", isHuman: false),
            RunFastPlayer(name: "AI 右", isHuman: false)
        ]
        let hands = Self.deal(deck: deck)
        let first = startingPlayer ?? Self.findSpadeThreeHolder(in: hands) ?? 0
        self.state = RunFastState(players: players, hands: hands, currentPlayerIndex: first)
        appendSystemEvent("黑桃3先出")
    }

    public init(players: [RunFastPlayer], hands: [[Card]], startingPlayer: Int) {
        self.state = RunFastState(players: players, hands: hands, currentPlayerIndex: startingPlayer)
    }

    public init(state: RunFastState) {
        self.state = state
    }

    public static func playableDeck() -> [Card] {
        DeckConfig(deckCount: 1).makeDeck().filter { $0.rank != .smallJoker && $0.rank != .bigJoker }
    }

    public static func deal(deck: [Card]) -> [[Card]] {
        let playable = Array(deck.filter { $0.rank != .smallJoker && $0.rank != .bigJoker }.prefix(48))
        var hands = Array(repeating: [Card](), count: 3)
        for (index, card) in playable.enumerated() {
            hands[index % 3].append(card)
        }
        return hands.map { $0.sortedForHand() }
    }

    public static func findSpadeThreeHolder(in hands: [[Card]]) -> Int? {
        hands.firstIndex { hand in
            hand.contains { $0.rank == .three && $0.suit == .spades }
        }
    }

    public func legalActions(for playerIndex: Int) -> [RunFastAction] {
        guard state.phase == .playing, state.currentPlayerIndex == playerIndex else { return [] }
        let previous = activePreviousCombination(for: playerIndex)
        var plays = RunFastRulesEngine.legalCombinations(in: state.hands[playerIndex], beating: previous)
            .map { RunFastAction.play($0.cards) }
        if isOpeningLead,
           state.players[playerIndex].isHuman || playerIndex == state.currentPlayerIndex,
           let spadeThree = state.hands[playerIndex].first(where: { $0.rank == .three && $0.suit == .spades }) {
            plays = plays.filter { $0.cards.contains(spadeThree) }
        }
        if previous == nil {
            return plays
        }
        return plays + [.pass]
    }

    public func apply(_ action: RunFastAction) throws {
        guard state.phase == .playing else { throw RunFastError.gameOver }
        let playerIndex = state.currentPlayerIndex
        switch action {
        case .pass:
            try pass(playerIndex)
        case .play(let cards):
            try play(cards, by: playerIndex)
        }
    }
}

private extension RunFastGameEngine {
    func activePreviousCombination(for playerIndex: Int) -> RunFastCombination? {
        guard let lastPlay = state.lastPlay,
              lastPlay.playerIndex != playerIndex
        else { return nil }
        return lastPlay.combination
    }

    var isOpeningLead: Bool {
        state.lastPlay == nil && state.playActionCounts.allSatisfy { $0 == 0 }
    }

    func play(_ cards: [Card], by playerIndex: Int) throws {
        guard Set(cards).isSubset(of: Set(state.hands[playerIndex])) else {
            throw RunFastError.cardsNotInHand
        }
        guard let combination = RunFastRulesEngine.classify(cards) else {
            throw RunFastError.invalidCombination
        }
        if isOpeningLead,
           state.hands[playerIndex].contains(where: { $0.rank == .three && $0.suit == .spades }),
           !cards.contains(where: { $0.rank == .three && $0.suit == .spades }) {
            throw RunFastError.firstPlayMustContainSpadeThree
        }
        if let previous = activePreviousCombination(for: playerIndex),
           !RunFastRulesEngine.canBeat(combination, previous) {
            throw RunFastError.cannotBeatPrevious
        }

        state.hands[playerIndex] = state.hands[playerIndex].removing(cards).sortedForHand()
        state.playActionCounts[playerIndex] += 1
        state.passCount = 0

        let record = RunFastPlayRecord(
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
            finishGame(winningPlayer: playerIndex)
            return
        }

        state.currentPlayerIndex = nextPlayer(after: playerIndex)
    }

    func pass(_ playerIndex: Int) throws {
        guard activePreviousCombination(for: playerIndex) != nil else {
            throw RunFastError.cannotPassOnLead
        }

        let record = RunFastPlayRecord(
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

        if state.passCount >= state.players.count - 1, let controller = state.lastPlay?.playerIndex {
            state.currentPlayerIndex = controller
            state.lastPlay = nil
            state.passCount = 0
            clearTableRecords(keeping: controller)
            appendSystemEvent("\(state.players[controller].name)重新出牌")
        } else {
            state.currentPlayerIndex = nextPlayer(after: playerIndex)
        }
    }

    func finishGame(winningPlayer: Int) {
        state.phase = .gameOver
        state.winnerIndex = winningPlayer
        state.scores = state.players.indices.map { index in
            let remaining = state.hands[index].count
            let delta = index == winningPlayer ?
                state.hands.indices.filter { $0 != winningPlayer }.map { state.hands[$0].count }.reduce(0, +) :
                -remaining
            return RunFastScoreLine(
                playerIndex: index,
                playerName: state.players[index].name,
                remainingCards: remaining,
                delta: delta
            )
        }
        appendSystemEvent("\(state.players[winningPlayer].name)跑完")
    }

    func nextPlayer(after playerIndex: Int) -> Int {
        (playerIndex + 1) % state.players.count
    }

    func setTableRecord(_ record: RunFastPlayRecord) {
        guard state.tableRecords.indices.contains(record.playerIndex) else { return }
        state.tableRecords[record.playerIndex] = record
    }

    func clearTableRecords(keeping playerIndex: Int? = nil) {
        for index in state.tableRecords.indices where index != playerIndex {
            state.tableRecords[index] = nil
        }
    }

    func appendSystemEvent(_ message: String) {
        let record = RunFastPlayRecord(
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

public struct RunFastAIPlayer: Sendable {
    public init() {}

    public func chooseAction(state: RunFastState, for playerIndex: Int) -> RunFastAction {
        let engine = RunFastGameEngine(state: state)
        let actions = engine.legalActions(for: playerIndex)
        guard !actions.isEmpty else { return .pass }
        if let finishing = actions.first(where: { !$0.cards.isEmpty && $0.cards.count == state.hands[playerIndex].count }) {
            return finishing
        }
        return actions.max { score($0, state: state, playerIndex: playerIndex) < score($1, state: state, playerIndex: playerIndex) } ?? actions[0]
    }

    public func legalActions(from state: RunFastState, for playerIndex: Int) -> [RunFastAction] {
        RunFastGameEngine(state: state).legalActions(for: playerIndex)
    }

    private func score(_ action: RunFastAction, state: RunFastState, playerIndex: Int) -> Int {
        guard !action.cards.isEmpty else {
            return passScore(state: state, playerIndex: playerIndex)
        }
        guard let combination = RunFastRulesEngine.classify(action.cards) else { return -100_000 }
        let hand = state.hands[playerIndex]
        let remaining = hand.removing(action.cards)
        let beforeTurns = turnEstimate(hand)
        let afterTurns = turnEstimate(remaining)
        let pressure = tablePressure(state: state, playerIndex: playerIndex)
        let minOpponent = state.hands.indices.filter { $0 != playerIndex }.map { state.hands[$0].count }.min() ?? 16

        var value = (beforeTurns - afterTurns) * 680 + action.cards.count * 45 - combination.primaryRank.rawValue * 12
        switch combination.kind {
        case .singleStraight:
            value += 780 + combination.sequenceLength * 80
        case .pairStraight:
            value += 900 + combination.sequenceLength * 105
        case .airplane, .airplaneWithWings:
            value += 860 + combination.sequenceLength * 130
        case .trioWithTwo:
            value += hand.count <= 7 ? 520 : 160
        case .bomb:
            value -= max(260, 1_600 - pressure * 18)
            if minOpponent <= 3 { value += 860 }
        case .single:
            if minOpponent == 1 { value -= 520 }
            value += combination.primaryRank.rawValue <= Rank.ten.rawValue ? 180 : -80
        case .pair:
            value += minOpponent == 1 ? 320 : 120
        case .trio:
            value += hand.count <= 5 ? 260 : -120
        }

        if state.lastPlay != nil && state.lastPlay?.playerIndex != playerIndex {
            value += 260 + pressure * 7
            if combination.kind == .bomb {
                value += pressure * 9
            }
        }
        if remaining.count <= 3 {
            value += 420
        }
        if minOpponent <= 2 && blocksShortOpponent(combination) {
            value += 540 + pressure * 8
        }
        return value
    }

    private func passScore(state: RunFastState, playerIndex: Int) -> Int {
        let pressure = tablePressure(state: state, playerIndex: playerIndex)
        let nextPlayer = (playerIndex + 1) % state.players.count
        let nextShort = state.hands.indices.contains(nextPlayer) ? state.hands[nextPlayer].count <= 3 : false
        return -pressure * (nextShort ? 16 : 8)
    }

    private func tablePressure(state: RunFastState, playerIndex: Int) -> Int {
        let minOpponent = state.hands.indices
            .filter { $0 != playerIndex }
            .map { state.hands[$0].count }
            .min() ?? 16
        let played = state.playActionCounts.reduce(0, +)
        return min(100, max(0, 72 - minOpponent * 8) + played * 3 + state.passCount * 4)
    }

    private func turnEstimate(_ cards: [Card]) -> Int {
        guard !cards.isEmpty else { return 0 }
        if RunFastRulesEngine.classify(cards) != nil { return 1 }
        var remaining = cards.sortedForHand()
        var turns = 0
        while !remaining.isEmpty && turns < 40 {
            guard let next = RunFastRulesEngine.legalCombinations(in: remaining).max(by: { planningScore($0) < planningScore($1) }) else {
                return turns + remaining.count
            }
            remaining = remaining.removing(next.cards)
            turns += 1
        }
        return turns + remaining.count
    }

    private func planningScore(_ combination: RunFastCombination) -> Int {
        var score = combination.cards.count * 260 - combination.primaryRank.rawValue * 8
        switch combination.kind {
        case .singleStraight:
            score += 700 + combination.sequenceLength * 70
        case .pairStraight:
            score += 840 + combination.sequenceLength * 90
        case .airplane, .airplaneWithWings:
            score += 920 + combination.sequenceLength * 110
        case .trioWithTwo:
            score += 260
        case .bomb:
            score += 180
        case .single, .pair, .trio:
            break
        }
        return score
    }

    private func blocksShortOpponent(_ combination: RunFastCombination) -> Bool {
        switch combination.kind {
        case .single:
            return false
        case .pair, .trio, .trioWithTwo, .singleStraight, .pairStraight, .airplane, .airplaneWithWings, .bomb:
            return true
        }
    }
}

public enum RunFastHintEngine {
    public static func bestAction(state: RunFastState, for playerIndex: Int) -> RunFastAction? {
        let action = RunFastAIPlayer().chooseAction(state: state, for: playerIndex)
        return action.cards.isEmpty ? nil : action
    }
}

private extension Array where Element == RunFastCombination {
    func sortedForRunFastDecision() -> [RunFastCombination] {
        sorted {
            let lhsScore = RunFastRulesEngine.combinationSortScore($0)
            let rhsScore = RunFastRulesEngine.combinationSortScore($1)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return $0.cards.count < $1.cards.count
        }
    }
}

private extension Array where Element == Rank {
    var areConsecutive: Bool {
        guard count > 1 else { return true }
        for index in 1..<count {
            guard self[index].rawValue == self[index - 1].rawValue + 1 else { return false }
        }
        return true
    }

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

    func removingFirst(count: Int, forEach ranks: [Rank]) -> [Card] {
        var remaining = self
        for rank in ranks {
            var removed = 0
            while removed < count, let index = remaining.firstIndex(where: { $0.rank == rank }) {
                remaining.remove(at: index)
                removed += 1
            }
        }
        return remaining
    }
}
