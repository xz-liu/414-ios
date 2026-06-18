import Foundation

private enum ReactionKind {
    case cha
    case gou
}

private struct PendingReaction {
    var kind: ReactionKind
    var rank: Rank
    var sourcePlayer: Int
    var remainingPlayers: [Int]
    var normalPlayPlayer: Int?
}

public final class GameEngine {
    public private(set) var state: GameState
    private var pendingReaction: PendingReaction?

    public convenience init(deckCount: Int = 1, playerCount: Int = 4) {
        var deck = DeckConfig(deckCount: deckCount).makeDeck()
        deck.shuffle()
        self.init(deckCount: deckCount, deck: deck, playerCount: playerCount)
    }

    public init(deckCount: Int, deck: [Card], playerCount: Int = 4) {
        let players = Self.defaultPlayers(playerCount: playerCount)
        let hands = Self.deal(deck: deck, playerCount: players.count)
        let starter = Self.findHeartThreeHolder(in: hands) ?? 0
        self.state = GameState(
            deckCount: deckCount,
            players: players,
            hands: hands,
            prompt: TurnPrompt(kind: .lead, playerIndex: starter)
        )
        appendSystemEvent("红桃3在\(players[starter].name)手中，\(players[starter].name)先出")
    }

    public init(deckCount: Int = 1, players: [GamePlayer], hands: [[Card]], startingPlayer: Int) {
        precondition(players.count == hands.count)
        self.state = GameState(
            deckCount: deckCount,
            players: players,
            hands: hands,
            prompt: TurnPrompt(kind: .lead, playerIndex: startingPlayer)
        )
    }

    public func legalActions(for playerIndex: Int) -> [PlayerAction] {
        guard state.prompt.playerIndex == playerIndex, !state.isGameOver else { return [] }
        switch state.prompt.kind {
        case .lead:
            return RulesEngine.legalCombinations(in: state.hands[playerIndex]).map { .play($0.cards) }
        case .follow:
            guard let previous = state.lastPlayableRecord?.combination else { return [] }
            let plays = RulesEngine.legalCombinations(in: state.hands[playerIndex], beating: previous).map {
                PlayerAction.play($0.cards)
            }
            return plays + [.pass]
        case .cha:
            guard let rank = state.prompt.baseRank,
                  let cards = RulesEngine.legalChaCards(in: state.hands[playerIndex], rank: rank)
            else { return [.pass] }
            return [.cha(cards), .pass]
        case .gou:
            guard let rank = state.prompt.baseRank,
                  let card = RulesEngine.legalGouCard(in: state.hands[playerIndex], rank: rank)
            else { return [.pass] }
            return [.gou(card), .pass]
        case .gameOver:
            return []
        }
    }

    public func apply(_ action: PlayerAction) throws {
        guard !state.isGameOver else { throw GameError.gameOver }
        guard let playerIndex = state.prompt.playerIndex else { throw GameError.notPlayersTurn }

        switch (state.prompt.kind, action) {
        case (.lead, .play(let cards)):
            try play(cards, by: playerIndex, mustBeat: nil)
        case (.lead, .pass):
            throw GameError.cannotPassOnLead
        case (.follow, .play(let cards)):
            guard let previous = state.lastPlayableRecord?.combination else {
                throw GameError.illegalAction
            }
            try play(cards, by: playerIndex, mustBeat: previous)
        case (.follow, .pass):
            passFollow(by: playerIndex)
        case (.cha, .cha(let cards)):
            try cha(cards, by: playerIndex)
        case (.cha, .pass):
            passReaction(by: playerIndex)
        case (.gou, .gou(let card)):
            try gou(card, by: playerIndex)
        case (.gou, .pass):
            passReaction(by: playerIndex)
        default:
            throw GameError.illegalAction
        }
    }
}

public extension GameEngine {
    static func defaultPlayers(playerCount: Int) -> [GamePlayer] {
        precondition((3...4).contains(playerCount), "414 only supports 3 or 4 players")
        if playerCount == 3 {
            return [
                GamePlayer(name: "你", isHuman: true),
                GamePlayer(name: "AI 左", isHuman: false),
                GamePlayer(name: "AI 右", isHuman: false)
            ]
        }
        return [
            GamePlayer(name: "你", isHuman: true),
            GamePlayer(name: "AI 左", isHuman: false),
            GamePlayer(name: "AI 上", isHuman: false),
            GamePlayer(name: "AI 右", isHuman: false)
        ]
    }

    static func deal(deck: [Card], playerCount: Int) -> [[Card]] {
        var hands = Array(repeating: [Card](), count: playerCount)
        for (index, card) in deck.enumerated() {
            hands[index % playerCount].append(card)
        }
        return hands.map { $0.sortedForHand() }
    }

    static func findHeartThreeHolder(in hands: [[Card]]) -> Int? {
        hands.firstIndex { hand in
            hand.contains { $0.isHeartThree }
        }
    }
}

private extension GameEngine {
    func play(_ cards: [Card], by playerIndex: Int, mustBeat previous: Combination?) throws {
        try ensure(cards, areInHandOf: playerIndex)
        guard let combination = RulesEngine.classify(cards) else {
            throw GameError.invalidCombination
        }
        if let previous, !RulesEngine.canBeat(combination, previous) {
            throw GameError.cannotBeatPrevious
        }

        remove(cards, from: playerIndex)
        let record = PlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: combination,
            kind: .normal,
            message: "\(state.players[playerIndex].name)出\(combination.displayName)"
        )
        state.lastPlayableRecord = record
        state.visibleRecord = record
        state.eventLog.append(record)
        state.passCount = 0

        if finishIfNeeded(after: playerIndex) {
            return
        }

        if combination.kind == .single, let rank = combination.primaryRank {
            beginReaction(.cha, rank: rank, sourcePlayer: playerIndex, normalPlayPlayer: playerIndex)
        } else {
            setFollowPrompt(after: playerIndex)
        }
    }

    func cha(_ cards: [Card], by playerIndex: Int) throws {
        guard case .cha = state.prompt.kind, let rank = state.prompt.baseRank else {
            throw GameError.illegalAction
        }
        try ensure(cards, areInHandOf: playerIndex)
        guard cards.count == 2, cards.allSatisfy({ $0.rank == rank }) else {
            throw GameError.illegalAction
        }

        remove(cards, from: playerIndex)
        let combination = Combination(kind: .cha, cards: cards, primaryRank: rank, sameRankCount: 2)
        let record = PlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: combination,
            kind: .cha,
            message: "\(state.players[playerIndex].name)叉\(rank.label)"
        )
        state.visibleRecord = record
        state.eventLog.append(record)
        pendingReaction = nil

        if finishIfNeeded(after: playerIndex) {
            return
        }

        beginReaction(.gou, rank: rank, sourcePlayer: playerIndex, normalPlayPlayer: nil)
    }

    func gou(_ card: Card, by playerIndex: Int) throws {
        guard case .gou = state.prompt.kind, let rank = state.prompt.baseRank else {
            throw GameError.illegalAction
        }
        try ensure([card], areInHandOf: playerIndex)
        guard card.rank == rank else {
            throw GameError.illegalAction
        }

        remove([card], from: playerIndex)
        let combination = Combination(kind: .gou, cards: [card], primaryRank: rank, sameRankCount: 1)
        let record = PlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: combination,
            kind: .gou,
            message: "\(state.players[playerIndex].name)勾\(rank.label)"
        )
        state.visibleRecord = record
        state.eventLog.append(record)
        pendingReaction = nil

        if finishIfNeeded(after: playerIndex) {
            return
        }

        state.lastPlayableRecord = nil
        state.passCount = 0
        state.prompt = TurnPrompt(kind: .lead, playerIndex: playerIndex)
    }

    func passFollow(by playerIndex: Int) {
        let record = PlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: nil,
            kind: .pass,
            message: "\(state.players[playerIndex].name)过"
        )
        state.visibleRecord = record
        state.eventLog.append(record)
        state.passCount += 1

        if state.passCount >= state.players.count - 1, let leader = state.lastPlayableRecord?.playerIndex {
            state.lastPlayableRecord = nil
            state.passCount = 0
            state.prompt = TurnPrompt(kind: .lead, playerIndex: leader)
            appendSystemEvent("\(state.players.count - 1)家过牌，\(state.players[leader].name)重新起手")
        } else {
            setFollowPrompt(after: playerIndex)
        }
    }

    func passReaction(by playerIndex: Int) {
        guard var reaction = pendingReaction else { return }
        reaction.remainingPlayers.removeAll { $0 == playerIndex }
        pendingReaction = reaction
        advanceReactionOrFinish()
    }

    func beginReaction(_ kind: ReactionKind, rank: Rank, sourcePlayer: Int, normalPlayPlayer: Int?) {
        let candidates = playerOrder(after: sourcePlayer).filter { index in
            switch kind {
            case .cha:
                return index != sourcePlayer && RulesEngine.legalChaCards(in: state.hands[index], rank: rank) != nil
            case .gou:
                return index != sourcePlayer && RulesEngine.legalGouCard(in: state.hands[index], rank: rank) != nil
            }
        }
        pendingReaction = PendingReaction(
            kind: kind,
            rank: rank,
            sourcePlayer: sourcePlayer,
            remainingPlayers: candidates,
            normalPlayPlayer: normalPlayPlayer
        )
        advanceReactionOrFinish()
    }

    func advanceReactionOrFinish() {
        guard var reaction = pendingReaction else { return }
        while let next = reaction.remainingPlayers.first {
            let stillEligible: Bool
            switch reaction.kind {
            case .cha:
                stillEligible = RulesEngine.legalChaCards(in: state.hands[next], rank: reaction.rank) != nil
            case .gou:
                stillEligible = RulesEngine.legalGouCard(in: state.hands[next], rank: reaction.rank) != nil
            }
            if stillEligible {
                pendingReaction = reaction
                state.prompt = TurnPrompt(
                    kind: reaction.kind == .cha ? .cha : .gou,
                    playerIndex: next,
                    baseRank: reaction.rank
                )
                return
            }
            reaction.remainingPlayers.removeFirst()
        }

        pendingReaction = nil
        switch reaction.kind {
        case .cha:
            if let player = reaction.normalPlayPlayer {
                setFollowPrompt(after: player)
            }
        case .gou:
            state.lastPlayableRecord = nil
            state.passCount = 0
            state.prompt = TurnPrompt(kind: .lead, playerIndex: reaction.sourcePlayer)
            appendSystemEvent("无人勾，\(state.players[reaction.sourcePlayer].name)死叉后起手")
        }
    }

    func setFollowPrompt(after playerIndex: Int) {
        state.prompt = TurnPrompt(kind: .follow, playerIndex: nextPlayer(after: playerIndex))
    }

    func nextPlayer(after playerIndex: Int) -> Int {
        (playerIndex + 1) % state.players.count
    }

    func playerOrder(after playerIndex: Int) -> [Int] {
        (1..<state.players.count).map { offset in
            (playerIndex + offset) % state.players.count
        }
    }

    func ensure(_ cards: [Card], areInHandOf playerIndex: Int) throws {
        var hand = state.hands[playerIndex]
        for card in cards {
            guard let index = hand.firstIndex(of: card) else {
                throw GameError.cardsNotInHand
            }
            hand.remove(at: index)
        }
    }

    func remove(_ cards: [Card], from playerIndex: Int) {
        for card in cards {
            if let index = state.hands[playerIndex].firstIndex(of: card) {
                state.hands[playerIndex].remove(at: index)
            }
        }
        state.hands[playerIndex].sort()
        state.cardsPlayedCount[playerIndex] += cards.count
    }

    @discardableResult
    func finishIfNeeded(after playerIndex: Int) -> Bool {
        guard state.hands[playerIndex].isEmpty else { return false }
        state.winnerIndex = playerIndex
        state.prompt = .gameOver
        state.lastPlayableRecord = nil
        pendingReaction = nil
        state.scores = makeScores(winnerIndex: playerIndex)
        appendSystemEvent("\(state.players[playerIndex].name)率先出完，游戏结束")
        return true
    }

    func makeScores(winnerIndex: Int) -> [ScoreLine] {
        state.players.indices.map { index in
            if index == winnerIndex {
                return ScoreLine(
                    playerIndex: index,
                    playerName: state.players[index].name,
                    remainingCards: 0,
                    multiplier: 0,
                    penalty: 0,
                    notes: ["赢家"]
                )
            }

            let hand = state.hands[index]
            var multiplier = 1
            var notes: [String] = []
            if hand.containsRocket414() || hand.containsDoubleJoker() {
                multiplier *= 2
                notes.append("留有4A4或双王")
            }
            if state.cardsPlayedCount[index] == 0 {
                multiplier *= 2
                notes.append("未出过牌")
            }
            let penalty = hand.count * multiplier
            return ScoreLine(
                playerIndex: index,
                playerName: state.players[index].name,
                remainingCards: hand.count,
                multiplier: multiplier,
                penalty: penalty,
                notes: notes
            )
        }
    }

    func appendSystemEvent(_ message: String) {
        let record = PlayRecord(
            playerIndex: -1,
            playerName: "系统",
            combination: nil,
            kind: .system,
            message: message
        )
        state.visibleRecord = record
        state.eventLog.append(record)
    }
}
