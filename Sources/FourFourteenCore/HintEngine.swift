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
        let publicMemory = PublicCardMemory(state: state, playerIndex: playerIndex)

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
                followHintScore(lhs, state: state, memory: publicMemory) <
                    followHintScore(rhs, state: state, memory: publicMemory)
            }.first
        case .lead:
            return playable.sorted { lhs, rhs in
                leadHintScore(lhs, handCount: handCount, memory: publicMemory) <
                    leadHintScore(rhs, handCount: handCount, memory: publicMemory)
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

    static func followHintScore(_ action: PlayerAction, state: GameState, memory: PublicCardMemory) -> Int {
        guard let combination = combination(for: action) else { return Int.max }
        var score = RulesEngine.combinationSortScore(combination)
        if combination.isBombLike {
            score += 80_000
            if state.lastPlayableRecord?.combination?.isBombLike == true {
                score += controlSpendScore(combination) / 4
            }
            score += publicMemoryReservePenalty(for: combination, memory: memory)
        }
        score += action.cards.reduce(0) { $0 + controlPenalty(for: $1) }
        return score
    }

    static func leadHintScore(_ action: PlayerAction, handCount: Int, memory: PublicCardMemory) -> Int {
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
            score += 24_000 + publicMemoryReservePenalty(for: combination, memory: memory) / 2
        case .doubleJoker:
            score += 28_000 + publicMemoryReservePenalty(for: combination, memory: memory) / 2
        case .rocket414:
            score += 32_000
        case .cha, .gou:
            break
        }
        score += action.cards.reduce(0) { $0 + controlPenalty(for: $1) }
        return score
    }

    static func publicMemoryReservePenalty(for combination: Combination, memory: PublicCardMemory) -> Int {
        switch combination.kind {
        case .sameRankBomb:
            let canBeBeaten = memory.opponentsCanBeatSameRankBomb(combination) ||
                memory.opponentsCanHaveDoubleJoker ||
                memory.opponentsCanHaveRocket414
            return canBeBeaten ? 0 : 2_400
        case .doubleJoker:
            return memory.opponentsCanHaveRocket414 ? 0 : 3_400
        case .rocket414:
            return 4_600
        default:
            return 0
        }
    }

    static func controlSpendScore(_ combination: Combination) -> Int {
        let cardCost = combination.cards.reduce(0) { $0 + controlPenalty(for: $1) }
        switch combination.kind {
        case .sameRankBomb:
            return 10_000 + combination.sameRankCount * 2_200 + (combination.primaryRank?.rawValue ?? 0) * 120 + cardCost
        case .doubleJoker:
            return 45_000 + cardCost
        case .rocket414:
            return 55_000 + cardCost
        default:
            return RulesEngine.combinationSortScore(combination) + cardCost
        }
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
