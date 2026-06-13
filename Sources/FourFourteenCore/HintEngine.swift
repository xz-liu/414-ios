import Foundation

public enum HintEngine {
    public static func bestAction(state: GameState, for playerIndex: Int) -> PlayerAction? {
        guard state.prompt.playerIndex == playerIndex else { return nil }
        let ai = AIPlayer()
        let legal = ai.legalActions(from: state, for: playerIndex)
        guard !legal.isEmpty else { return nil }

        let quick = quickAction(state: state, for: playerIndex, legalActions: legal)
        if shouldUseQuickOnly(state: state, legalActionCount: legal.count) {
            return quick
        }

        let chosen = ai.chooseAction(state: state, for: playerIndex)
        if legal.contains(chosen), chosen.cards.isEmpty == false {
            return chosen
        }
        return quick ?? legal.first { !$0.cards.isEmpty }
    }

    public static func quickAction(state: GameState, for playerIndex: Int) -> PlayerAction? {
        guard state.prompt.playerIndex == playerIndex else { return nil }
        let legal = AIPlayer().legalActions(from: state, for: playerIndex)
        return quickAction(state: state, for: playerIndex, legalActions: legal)
    }
}

private extension HintEngine {
    static func quickAction(
        state: GameState,
        for playerIndex: Int,
        legalActions: [PlayerAction]
    ) -> PlayerAction? {
        let handCount = state.hands.indices.contains(playerIndex) ? state.hands[playerIndex].count : 0
        let playable = legalActions.filter { !$0.cards.isEmpty }
        guard !playable.isEmpty else { return nil }

        if let finishing = playable.first(where: { $0.cards.count == handCount }) {
            return finishing
        }

        switch state.prompt.kind {
        case .cha:
            return playable.first {
                if case .cha = $0 { return true }
                return false
            }
        case .gou:
            return playable.first {
                if case .gou = $0 { return true }
                return false
            }
        case .follow:
            return playable.sorted { lhs, rhs in
                followHintScore(lhs) < followHintScore(rhs)
            }.first
        case .lead:
            return playable.sorted { lhs, rhs in
                leadHintScore(lhs, handCount: handCount) < leadHintScore(rhs, handCount: handCount)
            }.first
        case .gameOver:
            return nil
        }
    }

    static func shouldUseQuickOnly(state: GameState, legalActionCount: Int) -> Bool {
        if state.deckCount > 1, legalActionCount > 28 {
            return true
        }
        return legalActionCount > 48
    }

    static func followHintScore(_ action: PlayerAction) -> Int {
        guard let combination = combination(for: action) else { return Int.max }
        var score = RulesEngine.combinationSortScore(combination)
        if combination.isBombLike {
            score += 80_000
        }
        score += action.cards.reduce(0) { $0 + controlPenalty(for: $1) }
        return score
    }

    static func leadHintScore(_ action: PlayerAction, handCount: Int) -> Int {
        guard let combination = combination(for: action) else { return Int.max }
        if action.cards.count == handCount {
            return -100_000
        }

        var score = RulesEngine.combinationSortScore(combination)
        switch combination.kind {
        case .singleRun:
            score -= 3_200 + combination.sequenceLength * 140
        case .pairRun:
            score -= 3_000 + combination.sequenceLength * 150
        case .single:
            score -= 500
        case .pair:
            score -= 350
        case .triadWithSingle, .triadWithPair:
            score += handCount <= 7 ? -300 : 6_000
        case .sameRankBomb:
            score += 24_000
        case .doubleJoker:
            score += 28_000
        case .rocket414:
            score += 32_000
        case .cha, .gou:
            break
        }
        score += action.cards.reduce(0) { $0 + controlPenalty(for: $1) }
        return score
    }

    static func combination(for action: PlayerAction) -> Combination? {
        switch action {
        case .play(let cards), .cha(let cards):
            return RulesEngine.classify(cards)
        case .gou(let card):
            return RulesEngine.classify([card])
        case .pass:
            return nil
        }
    }

    static func controlPenalty(for card: Card) -> Int {
        switch card.rank {
        case .bigJoker:
            return 8_000
        case .smallJoker:
            return 7_000
        case .two:
            return 4_200
        case .ace:
            return 850
        case .king:
            return 650
        default:
            return card.rank.rawValue * 20
        }
    }
}
