import Foundation

public struct DouDizhuAIPlayer: Sendable {
    public init() {}

    public func chooseBid(state: DouDizhuState, for playerIndex: Int) -> DouDizhuBidAction {
        let legal = legalBidActions(from: state, for: playerIndex)
        guard !legal.isEmpty else { return .pass }

        let score = handBidScore(state.hands[playerIndex])
        let targetBid: Int
        switch score {
        case 26...:
            targetBid = 3
        case 18...:
            targetBid = 2
        case 12...:
            targetBid = 1
        default:
            targetBid = 0
        }

        guard targetBid > state.highestBid else { return .pass }
        let bid = DouDizhuBidAction.bid(min(3, targetBid))
        return legal.contains(bid) ? bid : .pass
    }

    public func chooseAction(state: DouDizhuState, for playerIndex: Int) -> DouDizhuAction {
        let legal = legalPlayActions(from: state, for: playerIndex)
        guard !legal.isEmpty else { return .pass }

        let handCount = state.hands[playerIndex].count
        if let finishing = legal.first(where: { action in
            action.cards.count == handCount && !action.cards.isEmpty
        }) {
            return finishing
        }

        let playable = legal.filter { !$0.cards.isEmpty }
        guard !playable.isEmpty else { return .pass }

        if activePreviousCombination(state: state, playerIndex: playerIndex) != nil {
            let urgent = opponentMinimumCards(state: state, playerIndex: playerIndex) <= 2
            if !urgent, legal.contains(.pass) {
                let nonBomb = playable.filter { action in
                    DouDizhuRulesEngine.classify(action.cards)?.isBombLike == false
                }
                return nonBomb.sorted { followScore($0) < followScore($1) }.first ?? .pass
            }
            return playable.sorted { followScore($0) < followScore($1) }.first ?? .pass
        }

        return playable.sorted { leadScore($0, hand: state.hands[playerIndex]) < leadScore($1, hand: state.hands[playerIndex]) }.first ?? .pass
    }

    public func legalBidActions(from state: DouDizhuState, for playerIndex: Int) -> [DouDizhuBidAction] {
        guard state.phase == .bidding, state.currentPlayerIndex == playerIndex else { return [] }
        var actions: [DouDizhuBidAction] = [.pass]
        if state.highestBid < 3 {
            for value in (state.highestBid + 1)...3 {
                actions.append(.bid(value))
            }
        }
        return actions
    }

    public func legalPlayActions(from state: DouDizhuState, for playerIndex: Int) -> [DouDizhuAction] {
        guard state.phase == .playing, state.currentPlayerIndex == playerIndex else { return [] }
        let previous = activePreviousCombination(state: state, playerIndex: playerIndex)
        let plays = DouDizhuRulesEngine.legalCombinations(in: state.hands[playerIndex], beating: previous)
            .map { DouDizhuAction.play($0.cards) }
        if previous == nil {
            return plays
        }
        return plays + [.pass]
    }
}

private extension DouDizhuAIPlayer {
    func handBidScore(_ hand: [Card]) -> Int {
        let groups = Dictionary(grouping: hand, by: \.rank)
        var score = 0
        if hand.containsDoubleJoker() {
            score += 8
        }
        score += (groups[.two]?.count ?? 0) * 3
        score += (groups[.ace]?.count ?? 0) * 2
        score += groups.values.filter { $0.count == 4 }.count * 6
        score += groups.values.filter { $0.count == 3 }.count * 2
        score += longestStraightLength(in: hand) >= 5 ? 3 : 0
        return score
    }

    func activePreviousCombination(state: DouDizhuState, playerIndex: Int) -> DouDizhuCombination? {
        guard let lastPlay = state.lastPlay,
              lastPlay.playerIndex != playerIndex
        else { return nil }
        return lastPlay.combination
    }

    func opponentMinimumCards(state: DouDizhuState, playerIndex: Int) -> Int {
        state.hands.indices
            .filter { $0 != playerIndex }
            .map { state.hands[$0].count }
            .filter { $0 > 0 }
            .min() ?? 99
    }

    func followScore(_ action: DouDizhuAction) -> Int {
        guard let combination = DouDizhuRulesEngine.classify(action.cards) else { return Int.max }
        var score = DouDizhuRulesEngine.combinationSortScore(combination)
        if combination.isBombLike {
            score += 40_000
        }
        score += action.cards.reduce(0) { $0 + cardConservationPenalty($1) }
        return score
    }

    func leadScore(_ action: DouDizhuAction, hand: [Card]) -> Int {
        guard let combination = DouDizhuRulesEngine.classify(action.cards) else { return Int.max }
        if action.cards.count == hand.count {
            return -100_000
        }

        var score = DouDizhuRulesEngine.combinationSortScore(combination)
        switch combination.kind {
        case .singleStraight:
            score -= 5_000 + combination.sequenceLength * 90
        case .pairStraight:
            score -= 4_400 + combination.sequenceLength * 95
        case .airplane:
            score -= 4_000 + combination.sequenceLength * 120
        case .airplaneWithSingles, .airplaneWithPairs:
            score -= 3_800 + combination.sequenceLength * 100
        case .trioWithSingle, .trioWithPair:
            score -= 1_300
        case .single:
            score -= 700
        case .pair:
            score -= 500
        case .bomb, .rocket:
            score += 45_000
        case .trio, .fourWithTwoSingles, .fourWithTwoPairs:
            break
        }
        score += action.cards.reduce(0) { $0 + cardConservationPenalty($1) }
        return score
    }

    func cardConservationPenalty(_ card: Card) -> Int {
        switch card.rank {
        case .bigJoker:
            return 4_000
        case .smallJoker:
            return 3_600
        case .two:
            return 2_200
        case .ace:
            return 700
        case .king:
            return 520
        default:
            return card.rank.rawValue * 12
        }
    }

    func longestStraightLength(in hand: [Card]) -> Int {
        let groups = Dictionary(grouping: hand, by: \.rank)
        var best = 0
        var current = 0
        for rank in Rank.runRanks {
            if (groups[rank]?.isEmpty == false) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }
}
