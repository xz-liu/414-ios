import Foundation

public struct AIPlayer: Sendable {
    public init() {}

    public func chooseAction(state: GameState, for playerIndex: Int) -> PlayerAction {
        let actions = legalActions(from: state, for: playerIndex)
        guard !actions.isEmpty else { return .pass }

        if let finishing = actions.first(where: { action in
            action.cards.count == state.hands[playerIndex].count && !action.cards.isEmpty
        }) {
            return finishing
        }

        let candidates = boundedCandidateActions(actions, state: state, playerIndex: playerIndex)
        var evaluator = AIEvaluator(state: state, playerIndex: playerIndex, actions: candidates)
        return evaluator.chooseBestAction()
    }

    public func legalActions(from state: GameState, for playerIndex: Int) -> [PlayerAction] {
        guard state.prompt.playerIndex == playerIndex else { return [] }
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

    private func boundedCandidateActions(
        _ actions: [PlayerAction],
        state: GameState,
        playerIndex: Int
    ) -> [PlayerAction] {
        guard state.deckCount > 1 else { return actions }
        guard state.prompt.kind == .lead || state.prompt.kind == .follow else { return actions }

        let passActions = actions.filter(\.cards.isEmpty)
        let playActions = actions.filter { !$0.cards.isEmpty }
        let handCount = state.hands[playerIndex].count
        let limit = candidateLimit(handCount: handCount, prompt: state.prompt.kind)
        guard playActions.count > limit else { return actions }

        let ranked = playActions.map { action in
            let combination = RulesEngine.classify(action.cards)
            return (
                action: action,
                combination: combination,
                score: quickActionScore(action, combination: combination, state: state, playerIndex: playerIndex)
            )
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.action.cards.count > $1.action.cards.count
        }

        var selected: [PlayerAction] = []
        var seen = Set<PlayerAction>()
        func append(_ action: PlayerAction) {
            guard !seen.contains(action) else { return }
            seen.insert(action)
            selected.append(action)
        }

        ranked.prefix(limit).map(\.action).forEach(append)

        for kind in priorityKinds {
            if let action = ranked.first(where: { $0.combination?.kind == kind })?.action {
                append(action)
            }
        }

        passActions.forEach(append)
        return selected
    }

    private func candidateLimit(handCount: Int, prompt: PromptKind) -> Int {
        switch (prompt, handCount) {
        case (.lead, 40...):
            return 18
        case (.follow, 40...):
            return 24
        case (.lead, 20...):
            return 18
        case (.follow, 20...):
            return 26
        default:
            return 56
        }
    }

    private var priorityKinds: [CombinationKind] {
        [
            .singleRun,
            .pairRun,
            .single,
            .pair,
            .triadWithSingle,
            .triadWithPair,
            .sameRankBomb,
            .doubleJoker,
            .rocket414
        ]
    }

    private func quickActionScore(
        _ action: PlayerAction,
        combination: Combination?,
        state: GameState,
        playerIndex: Int
    ) -> Int {
        guard let combination else { return -100_000 }
        let hand = state.hands[playerIndex]
        let remaining = hand.removing(action.cards)
        let handCount = state.hands[playerIndex].count
        let rank = combination.primaryRank?.rawValue ?? 0
        let pressure = aiTablePressure(state: state, playerIndex: playerIndex)
        let threat = ThreatContext(state: state, playerIndex: playerIndex)
        let defenseIsUrgent = threat.defenseResponsibility >= 55

        var score = action.cards.count * 45 - rank * 10
        switch combination.kind {
        case .singleRun:
            score += 3_200 + combination.sequenceLength * 210
            let nextRunLength = bestSingleRunLength(in: remaining)
            if nextRunLength >= 3 {
                score += 850 + nextRunLength * 70
            } else if combination.sequenceLength >= 6,
                      duplicateRanksUsed(by: action.cards, in: hand) >= 2 {
                score -= 900
            }
        case .pairRun:
            score += 3_600 + combination.sequenceLength * 250
        case .single:
            score += 700 - rank * 18
            if let primaryRank = combination.primaryRank,
               hand.count(of: primaryRank) > 1,
               bestSingleRunLength(in: remaining) >= bestSingleRunLength(in: hand) {
                score += 360
            }
        case .pair:
            score += 880 - rank * 16
        case .triadWithSingle:
            score += handCount <= 8 ? 1_400 : 180
        case .triadWithPair:
            score += handCount <= 8 ? 1_650 : 240
        case .sameRankBomb:
            score += -1_600 + pressure * 8 + threat.defenseResponsibility * 24
            score -= combination.sameRankCount * 110
        case .doubleJoker, .rocket414:
            score += -2_200 + pressure * 10 + threat.defenseResponsibility * 28
        case .cha, .gou:
            break
        }

        if state.prompt.kind == .follow {
            score += 550 + pressure * 4 + threat.defenseResponsibility * 9
            if combination.isBombLike, !defenseIsUrgent {
                score -= max(260, 1_700 - threat.defenseResponsibility * 18 - pressure * 5)
            }
        }

        if action.cards.contains(where: { $0.rank == .two || $0.rank == .smallJoker || $0.rank == .bigJoker }),
           !defenseIsUrgent,
           handCount > 5 {
            score -= max(0, 1_250 - threat.defenseResponsibility * 14 - pressure * 4)
        }

        if threat.minimumThreatCards == 1 && (state.prompt.kind == .lead || state.prompt.kind == .follow) {
            if blocksSingleCardOut(combination) {
                score += 520 + threat.defenseResponsibility * 18 + pressure * 4
            } else if combination.kind == .single {
                score -= 420 + threat.defenseResponsibility * 7
            }
        }

        if state.prompt.kind == .lead {
            score += leadRestrictionScore(combination, threat: threat)
        }

        return score
    }

    private func bestSingleRunLength(in cards: [Card]) -> Int {
        let groups = Dictionary(grouping: cards, by: \.rank)
        var best = 0
        var current = 0
        for rank in Rank.runRanks {
            if (groups[rank]?.count ?? 0) >= 1 {
                current += 1
                if current >= 3 {
                    best = max(best, current)
                }
            } else {
                current = 0
            }
        }
        return best
    }

    private func duplicateRanksUsed(by cards: [Card], in hand: [Card]) -> Int {
        Set(cards.map(\.rank)).filter { hand.count(of: $0) > 1 }.count
    }

    private func leadRestrictionScore(_ combination: Combination, threat: ThreatContext) -> Int {
        guard let threatCards = threat.minimumThreatCards else { return 0 }
        switch threatCards {
        case 1:
            return blocksSingleCardOut(combination) ? 900 : (combination.kind == .single ? -650 : 0)
        case 2:
            if combination.cards.count >= 3 {
                return restrictiveShapeScore(combination) + 360
            }
            return combination.kind == .pair ? -260 : 0
        case 3:
            return restrictiveShapeScore(combination)
        default:
            return 0
        }
    }
}

private struct AIEvaluator {
    let state: GameState
    let playerIndex: Int
    let actions: [PlayerAction]
    var metricsCache: [String: PlanMetrics] = [:]

    var hand: [Card] {
        state.hands[playerIndex]
    }

    mutating func chooseBestAction() -> PlayerAction {
        var bestAction = actions[0]
        var bestScore = score(bestAction)

        for action in actions.dropFirst() {
            let actionScore = score(action)
            if actionScore > bestScore ||
                (actionScore == bestScore && tieBreakCost(action) < tieBreakCost(bestAction)) {
                bestAction = action
                bestScore = actionScore
            }
        }

        return bestAction
    }

    mutating func score(_ action: PlayerAction) -> Int {
        guard !action.cards.isEmpty else {
            return passScore()
        }

        if action.cards.count == hand.count {
            return 100_000
        }

        let combination = combination(for: action)
        let remaining = hand.removing(action.cards)
        let before = planMetrics(for: hand)
        let after = planMetrics(for: remaining)

        return actionBenefit(action, combination: combination, before: before, after: after)
            + singleCardOutDefenseScore(action, combination: combination)
            - resourceCost(action, combination: combination)
            - structureCost(action, combination: combination, before: before, after: after)
            - counterRisk(action, combination: combination)
            - overkillPenalty(action, combination: combination)
            - greedyRunPenalty(action, combination: combination, before: before, after: after)
            + endgameBonus(action, remaining: remaining)
    }

    func passScore() -> Int {
        switch state.prompt.kind {
        case .follow:
            let coveredPressure = tablePressure * 2 -
                threatContext.coverageStrength * 2 -
                threatContext.interceptReliabilityAfterMe
            return -max(0, coveredPressure) - threatContext.defenseResponsibility * 14
        case .cha, .gou:
            return 0
        case .lead, .gameOver:
            return -100_000
        }
    }

    func tieBreakCost(_ action: PlayerAction) -> Int {
        if action.cards.isEmpty {
            return 0
        }
        let combination = combination(for: action)
        return resourceCost(action, combination: combination) + action.cards.count
    }

    func combination(for action: PlayerAction) -> Combination? {
        switch action {
        case .play(let cards):
            return RulesEngine.classify(cards)
        case .cha(let cards):
            guard let rank = cards.first?.rank else { return nil }
            return Combination(kind: .cha, cards: cards, primaryRank: rank, sameRankCount: 2)
        case .gou(let card):
            return Combination(kind: .gou, cards: [card], primaryRank: card.rank, sameRankCount: 1)
        case .pass:
            return nil
        }
    }

    func actionBenefit(
        _ action: PlayerAction,
        combination: Combination?,
        before: PlanMetrics,
        after: PlanMetrics
    ) -> Int {
        let turnDelta = min(6, max(-4, before.estimatedTurns - after.estimatedTurns))
        var benefit = turnDelta * 520 + action.cards.count * 35

        switch state.prompt.kind {
        case .lead:
            benefit += 140
        case .follow:
            benefit += 220
            benefit += tablePressure * 5
            benefit += threatContext.defenseResponsibility * 12
            if hand.count <= 5 { benefit += 260 }
        case .cha:
            benefit += 360
            benefit += tablePressure * 4
            if threatContext.currentControllerIsThreat {
                benefit += threatContext.defenseResponsibility * 8
            }
        case .gou:
            benefit += 920
            benefit += tablePressure * 4
            if threatContext.currentControllerIsThreat {
                benefit += threatContext.defenseResponsibility * 7
            }
        case .gameOver:
            break
        }

        if let combination {
            switch combination.kind {
            case .singleRun:
                benefit += 280 + combination.sequenceLength * 35
            case .pairRun:
                benefit += 380 + combination.sequenceLength * 45
            case .triadWithSingle, .triadWithPair:
                benefit += hand.count <= 7 ? 240 : 0
            default:
                break
            }

            if state.prompt.kind == .follow {
                if combination.isBombLike {
                    benefit += tablePressure * 3 + threatContext.defenseResponsibility * 9
                }
                if action.cards.contains(where: isControlCard) {
                    benefit += tablePressure * 2 + threatContext.defenseResponsibility * 6
                }
            }
        }

        benefit += productiveShapeBenefit(action, combination: combination, before: before, after: after)
        return benefit
    }

    func productiveShapeBenefit(
        _ action: PlayerAction,
        combination: Combination?,
        before: PlanMetrics,
        after: PlanMetrics
    ) -> Int {
        guard let combination else { return 0 }
        var bonus = 0

        switch combination.kind {
        case .single:
            if let rank = combination.primaryRank,
               hand.count(of: rank) > 1,
               before.bestSingleRunLength >= 3,
               after.bestSingleRunLength >= before.bestSingleRunLength {
                bonus += 340
            }
        case .singleRun:
            if after.estimatedTurns == 1, after.bestSingleRunLength >= 3 {
                bonus += 520 + after.bestSingleRunLength * 55
            }
            if before.bestSingleRunLength >= 5,
               after.bestSingleRunLength >= 3,
               duplicateRanksUsed(by: action.cards) >= 1 {
                bonus += 260
            }
        case .pairRun:
            if after.estimatedTurns == 1, after.bestPairRunLength >= 3 {
                bonus += 560 + after.bestPairRunLength * 65
            }
        default:
            break
        }

        return bonus
    }

    func resourceCost(_ action: PlayerAction, combination: Combination?) -> Int {
        guard !action.cards.isEmpty else { return 0 }
        var cost = action.cards.reduce(0) { $0 + cardResourceValue($1) }

        if let combination {
            switch combination.kind {
            case .singleRun, .pairRun:
                cost /= 2
            case .sameRankBomb:
                if action.cards.count < hand.count {
                    cost += 820 + combination.sameRankCount * 180 + rankValue(combination.primaryRank) * 18
                }
            case .doubleJoker:
                cost += action.cards.count < hand.count ? 1_450 : 0
            case .rocket414:
                cost += action.cards.count < hand.count ? 1_850 : 0
            case .triadWithSingle:
                cost += hand.count <= 7 ? 260 : 840
                cost += attachmentPenalty(for: combination)
            case .triadWithPair:
                cost += hand.count <= 7 ? 320 : 1_080
                cost += attachmentPenalty(for: combination)
            case .cha:
                cost += combination.primaryRank == .two ? 1_150 : 180
            case .gou:
                cost += combination.primaryRank == .two ? 320 : 80
            default:
                break
            }
        }

        if isControlAction(action, combination: combination),
           ((combination?.kind != .cha && combination?.kind != .gou) || threatContext.currentControllerIsThreat) {
            cost = responsibilityDiscounted(cost, maxDiscount: 68)
        }
        return cost
    }

    func cardResourceValue(_ card: Card) -> Int {
        switch card.rank {
        case .bigJoker:
            return 1_050
        case .smallJoker:
            return 900
        case .two:
            return 520
        case .ace:
            return 180
        case .king:
            return 140
        case .queen:
            return 112
        case .jack:
            return 82
        case .ten:
            return 58
        default:
            return card.rank.rawValue * 6
        }
    }

    func attachmentPenalty(for combination: Combination) -> Int {
        guard combination.kind == .triadWithSingle || combination.kind == .triadWithPair else { return 0 }
        let groups = Dictionary(grouping: combination.cards, by: \.rank)
        guard let triadRank = groups.first(where: { $0.value.count == 3 })?.key else { return 0 }
        return combination.cards
            .filter { $0.rank != triadRank }
            .reduce(0) { partial, card in
                var penalty = cardResourceValue(card) / 2
                if card.rank == .two || card.rank == .smallJoker || card.rank == .bigJoker {
                    penalty += 420
                }
                if hand.count(of: card.rank) >= 2 {
                    penalty += 120
                }
                return partial + penalty
            }
    }

    func structureCost(
        _ action: PlayerAction,
        combination: Combination?,
        before: PlanMetrics,
        after: PlanMetrics
    ) -> Int {
        let rawDamage = max(0, before.structureValue - after.structureValue)
        guard rawDamage > 0 else { return 0 }

        guard let combination else { return rawDamage }
        switch combination.kind {
        case .singleRun, .pairRun:
            return max(0, rawDamage - 520) / 4
        case .sameRankBomb, .doubleJoker, .rocket414:
            return 0
        default:
            return rawDamage
        }
    }

    func counterRisk(_ action: PlayerAction, combination: Combination?) -> Int {
        guard let combination else { return 0 }

        switch combination.kind {
        case .single where state.prompt.kind == .lead || state.prompt.kind == .follow:
            return pressureDiscounted(singleChaRisk(rank: combination.primaryRank), maxDiscount: 72)
        case .cha:
            return pressureDiscounted(gouRisk(rank: combination.primaryRank), maxDiscount: 72)
        case .sameRankBomb, .doubleJoker, .rocket414:
            return bombCounterRisk(combination)
        default:
            return 0
        }
    }

    func singleChaRisk(rank: Rank?) -> Int {
        guard let rank, rank != .smallJoker, rank != .bigJoker else { return 0 }
        let potential = opponentRankPotential(rank)
        guard potential >= 2 else { return 0 }
        var risk = potential * 95 + rank.rawValue * 18
        if rank == .two { risk += 520 }
        return risk
    }

    func gouRisk(rank: Rank?) -> Int {
        guard let rank else { return 0 }
        let potential = opponentRankPotential(rank)
        guard potential > 0 else { return 0 }
        var risk = potential * 190 + rank.rawValue * 20
        if rank == .two { risk += 650 }
        if state.deckCount > 1 { risk += potential * 45 }
        return risk
    }

    func bombCounterRisk(_ combination: Combination) -> Int {
        guard threatContext.defenseResponsibility < 65 else { return 0 }
        switch combination.kind {
        case .doubleJoker, .rocket414:
            return 0
        case .sameRankBomb:
            let largerSameCountRanks = Rank.allCases.filter { rank in
                rank != .smallJoker &&
                    rank != .bigJoker &&
                    rank.rawValue > rankValue(combination.primaryRank) &&
                    opponentRankPotential(rank) >= combination.sameRankCount
            }.count
            let largerCountRisk = Rank.allCases.contains { rank in
                rank != .smallJoker &&
                    rank != .bigJoker &&
                    opponentRankPotential(rank) > combination.sameRankCount
            }
            return pressureDiscounted(
                largerSameCountRanks * 120 + (largerCountRisk ? 260 : 0),
                maxDiscount: 70
            )
        default:
            return 0
        }
    }

    func overkillPenalty(_ action: PlayerAction, combination: Combination?) -> Int {
        guard let combination else { return 0 }
        guard action.cards.count < hand.count else { return 0 }

        if threatContext.defenseResponsibility >= 65 || hand.count <= 4 {
            return unnecessaryControlPenalty(action, combination: combination)
        }

        var penalty = 0
        if state.prompt.kind == .follow,
           let previous = state.lastPlayableRecord?.combination,
           !previous.isBombLike {
            if combination.isBombLike {
                penalty += 1_150
            }
            if action.cards.contains(where: isControlCard) {
                penalty += rankValue(previous.primaryRank) <= Rank.ten.rawValue ? 760 : 520
            }
        }

        if state.prompt.kind == .lead {
            if combination.kind == .single && action.cards.contains(where: isControlCard) {
                penalty += 620
            }
            if combination.isBombLike {
                penalty += 680
            }
        }

        return responsibilityDiscounted(penalty, maxDiscount: 86) +
            unnecessaryControlPenalty(action, combination: combination)
    }

    func unnecessaryControlPenalty(_ action: PlayerAction, combination: Combination) -> Int {
        guard state.prompt.kind == .follow,
              let previous = state.lastPlayableRecord?.combination,
              !previous.isBombLike,
              combination.isBombLike
        else { return 0 }

        var penalty = 0
        if threatContext.coverageStrength >= 70 && !threatContext.currentControllerIsThreat {
            penalty += 1_250 + threatContext.coverageStrength * 5
        }
        if hasSufficientNonBombFollowAnswer() {
            penalty += 1_450
        }
        return penalty
    }

    func hasSufficientNonBombFollowAnswer() -> Bool {
        actions.contains { action in
            guard !action.cards.isEmpty,
                  let combination = combination(for: action),
                  !combination.isBombLike,
                  !action.cards.contains(where: isControlCard)
            else { return false }

            return isSufficientInterception(combination)
        }
    }

    func isSufficientInterception(_ combination: Combination) -> Bool {
        guard let threatCards = threatContext.minimumThreatCards else { return true }
        switch threatCards {
        case 1:
            return blocksSingleCardOut(combination)
        case 2:
            return combination.cards.count >= 3
        default:
            return true
        }
    }

    func greedyRunPenalty(
        _ action: PlayerAction,
        combination: Combination?,
        before: PlanMetrics,
        after: PlanMetrics
    ) -> Int {
        guard let combination else { return 0 }
        guard combination.kind == .singleRun else { return 0 }
        guard combination.sequenceLength >= 6 else { return 0 }
        guard duplicateRanksUsed(by: action.cards) >= 2 else { return 0 }
        guard after.bestSingleRunLength < 3 else { return 0 }
        guard before.estimatedTurns - after.estimatedTurns <= 0 else { return 0 }
        return 560
    }

    func endgameBonus(_ action: PlayerAction, remaining: [Card]) -> Int {
        var bonus = 0
        if remaining.count <= 3 {
            bonus += 260
        }
        if hand.count <= 6 && action.cards.count >= 3 {
            bonus += 180
        }
        if !action.cards.isEmpty {
            bonus += threatContext.defenseResponsibility * 2
        }
        if state.prompt.kind == .follow && !action.cards.isEmpty {
            bonus += tablePressure * 2
        }
        return bonus
    }

    func singleCardOutDefenseScore(_ action: PlayerAction, combination: Combination?) -> Int {
        guard let threatCards = threatContext.minimumThreatCards else { return 0 }
        guard state.prompt.kind == .lead || state.prompt.kind == .follow else { return 0 }
        guard action.cards.count < hand.count, let combination else { return 0 }

        switch threatCards {
        case 1:
            if blocksSingleCardOut(combination) {
                var bonus = 420 + threatContext.defenseResponsibility * 17 + tablePressure * 3
                if state.prompt.kind == .lead {
                    bonus += 420
                }
                switch combination.kind {
                case .sameRankBomb:
                    bonus -= 260
                case .doubleJoker:
                    bonus -= 520
                case .rocket414:
                    bonus -= 760
                default:
                    break
                }
                return max(260, bonus)
            }
            if combination.kind == .single {
                var penalty = 420 + threatContext.defenseResponsibility * 7
                if combination.primaryRank == .bigJoker && state.deckCount == 1 {
                    penalty /= 2
                }
                return -penalty
            }
        case 2:
            if combination.cards.count >= 3 {
                return 300 + restrictiveShapeScore(combination) + threatContext.defenseResponsibility * 8
            }
            if combination.kind == .pair {
                return -220
            }
        case 3:
            return restrictiveShapeScore(combination) + threatContext.defenseResponsibility * 3
        default:
            break
        }

        return 0
    }

    func isControlCard(_ card: Card) -> Bool {
        card.rank == .two || card.rank == .smallJoker || card.rank == .bigJoker
    }

    var tablePressure: Int {
        aiTablePressure(state: state, playerIndex: playerIndex)
    }

    var threatContext: ThreatContext {
        ThreatContext(state: state, playerIndex: playerIndex)
    }

    func pressureDiscounted(_ value: Int, maxDiscount: Int) -> Int {
        guard value > 0 else { return 0 }
        let discount = min(maxDiscount, max(tablePressure, threatContext.defenseResponsibility))
        return value * max(0, 100 - discount) / 100
    }

    func responsibilityDiscounted(_ value: Int, maxDiscount: Int) -> Int {
        guard value > 0 else { return 0 }
        let discount = min(maxDiscount, threatContext.defenseResponsibility)
        return value * max(0, 100 - discount) / 100
    }

    func isControlAction(_ action: PlayerAction, combination: Combination?) -> Bool {
        combination?.isBombLike == true || action.cards.contains(where: isControlCard)
    }

    func rankValue(_ rank: Rank?) -> Int {
        rank?.rawValue ?? -1
    }

    func opponentRankPotential(_ rank: Rank) -> Int {
        let totalRankCount = rank == .smallJoker || rank == .bigJoker ? state.deckCount : state.deckCount * 4
        let alreadyVisible = state.eventLog.reduce(0) { partial, record in
            partial + (record.combination?.cards.count(of: rank) ?? 0)
        }
        let ownCurrent = hand.count(of: rank)
        return max(0, totalRankCount - alreadyVisible - ownCurrent)
    }

    mutating func planMetrics(for cards: [Card]) -> PlanMetrics {
        let key = handSignature(cards)
        if let cached = metricsCache[key] {
            return cached
        }

        let groups = Dictionary(grouping: cards, by: \.rank)
        let metrics = PlanMetrics(
            estimatedTurns: estimatedTurns(for: cards),
            singletonCount: groups.values.filter { $0.count == 1 }.count,
            controlValue: controlValue(cards),
            structureValue: structureValue(cards),
            bestSingleRunLength: bestRunLength(groups: groups, repeatCount: 1),
            bestPairRunLength: bestRunLength(groups: groups, repeatCount: 2)
        )
        metricsCache[key] = metrics
        return metrics
    }

    func estimatedTurns(for cards: [Card]) -> Int {
        guard !cards.isEmpty else { return 0 }
        if RulesEngine.classify(cards) != nil { return 1 }
        if shouldUseFastTurnEstimate(cards) {
            return fastTurnEstimate(cards)
        }

        let best = greedyTurnEstimate(cards)
        var frontier = [SearchNode(cards: cards.sortedForHand(), turns: 0)]
        var seen: [String: Int] = [handSignature(cards): 0]
        var expansions = 0

        while !frontier.isEmpty && expansions < 800 {
            frontier.sort { searchPriority($0.cards, turns: $0.turns) < searchPriority($1.cards, turns: $1.turns) }
            let wave = Array(frontier.prefix(24))
            frontier.removeFirst(min(24, frontier.count))
            var next: [SearchNode] = []

            for node in wave {
                if node.turns >= best { continue }
                expansions += 1
                let candidates = planningCandidates(in: node.cards)
                for combination in candidates.prefix(24) {
                    let remaining = node.cards.removing(combination.cards)
                    let nextTurns = node.turns + 1
                    if remaining.isEmpty {
                        return min(best, nextTurns)
                    }
                    if nextTurns + lowerBoundTurns(remaining) >= best {
                        continue
                    }
                    let signature = handSignature(remaining)
                    if let previousTurns = seen[signature], previousTurns <= nextTurns {
                        continue
                    }
                    seen[signature] = nextTurns
                    next.append(SearchNode(cards: remaining, turns: nextTurns))
                }
                if expansions >= 800 { break }
            }

            frontier = Array(next
                .sorted { searchPriority($0.cards, turns: $0.turns) < searchPriority($1.cards, turns: $1.turns) }
                .prefix(24))
        }

        return best
    }

    func shouldUseFastTurnEstimate(_ cards: [Card]) -> Bool {
        cards.count > 30 || (state.deckCount > 1 && cards.count >= 12)
    }

    func fastTurnEstimate(_ cards: [Card]) -> Int {
        var counts = Dictionary(grouping: cards, by: \.rank).mapValues(\.count)
        var turns = 0

        while consumeBestRun(from: &counts, repeatCount: 2) {
            turns += 1
        }
        while consumeBestRun(from: &counts, repeatCount: 1) {
            turns += 1
        }

        let doubleJokers = min(counts[.smallJoker] ?? 0, counts[.bigJoker] ?? 0)
        if doubleJokers > 0 {
            turns += doubleJokers
            counts[.smallJoker] = (counts[.smallJoker] ?? 0) - doubleJokers
            counts[.bigJoker] = (counts[.bigJoker] ?? 0) - doubleJokers
        }

        for rank in Rank.allCases {
            let count = counts[rank] ?? 0
            guard count > 0 else { continue }
            turns += 1
        }

        return max(1, turns)
    }

    func consumeBestRun(from counts: inout [Rank: Int], repeatCount: Int) -> Bool {
        guard let (start, end) = bestRunToConsume(counts: counts, repeatCount: repeatCount) else { return false }
        for rank in Rank.runRanks[start...end] {
            counts[rank] = (counts[rank] ?? 0) - repeatCount
        }
        return true
    }

    func bestRunToConsume(counts: [Rank: Int], repeatCount: Int) -> (start: Int, end: Int)? {
        var best: (start: Int, end: Int, projectedTurns: Int)?
        let ranks = Rank.runRanks

        for start in ranks.indices {
            var end = start
            while end < ranks.count, (counts[ranks[end]] ?? 0) >= repeatCount {
                let length = end - start + 1
                if length >= 3 {
                    var simulated = counts
                    for rank in ranks[start...end] {
                        simulated[rank] = (simulated[rank] ?? 0) - repeatCount
                    }
                    let projected = cheapResidualTurnEstimate(simulated)
                    if best == nil ||
                        projected < best!.projectedTurns ||
                        (projected == best!.projectedTurns && length > best!.end - best!.start + 1) ||
                        (projected == best!.projectedTurns &&
                            length == best!.end - best!.start + 1 &&
                            start < best!.start) {
                        best = (start, end, projected)
                    }
                }
                end += 1
            }
        }

        guard let best else { return nil }
        return (best.start, best.end)
    }

    func cheapResidualTurnEstimate(_ counts: [Rank: Int]) -> Int {
        var remaining = counts
        var turns = 0
        while consumeLongestRun(from: &remaining, repeatCount: 2) {
            turns += 1
        }
        while consumeLongestRun(from: &remaining, repeatCount: 1) {
            turns += 1
        }

        let doubleJokers = min(remaining[.smallJoker] ?? 0, remaining[.bigJoker] ?? 0)
        if doubleJokers > 0 {
            turns += doubleJokers
            remaining[.smallJoker] = (remaining[.smallJoker] ?? 0) - doubleJokers
            remaining[.bigJoker] = (remaining[.bigJoker] ?? 0) - doubleJokers
        }

        for rank in Rank.allCases where (remaining[rank] ?? 0) > 0 {
            turns += 1
        }
        return turns
    }

    func consumeLongestRun(from counts: inout [Rank: Int], repeatCount: Int) -> Bool {
        var bestStart: Int?
        var bestEnd: Int?
        var currentStart: Int?

        for index in Rank.runRanks.indices {
            let rank = Rank.runRanks[index]
            if (counts[rank] ?? 0) >= repeatCount {
                if currentStart == nil {
                    currentStart = index
                }
                if let start = currentStart {
                    let length = index - start + 1
                    let bestLength = bestStart.flatMap { bestStart in
                        bestEnd.map { $0 - bestStart + 1 }
                    } ?? 0
                    if length >= 3 && length > bestLength {
                        bestStart = start
                        bestEnd = index
                    }
                }
            } else {
                currentStart = nil
            }
        }

        guard let bestStart, let bestEnd else { return false }
        for rank in Rank.runRanks[bestStart...bestEnd] {
            counts[rank] = (counts[rank] ?? 0) - repeatCount
        }
        return true
    }

    func greedyTurnEstimate(_ cards: [Card]) -> Int {
        var remaining = cards.sortedForHand()
        var turns = 0
        while !remaining.isEmpty && turns < 80 {
            guard let next = planningCandidates(in: remaining).first else {
                return turns + remaining.count
            }
            remaining = remaining.removing(next.cards)
            turns += 1
        }
        return turns + remaining.count
    }

    func lowerBoundTurns(_ cards: [Card]) -> Int {
        max(1, Int(ceil(Double(cards.count) / 8.0)))
    }

    func planningCandidates(in cards: [Card]) -> [Combination] {
        RulesEngine.legalCombinations(in: cards)
            .sorted { planningScore($0, fullHandCount: cards.count) > planningScore($1, fullHandCount: cards.count) }
    }

    func planningScore(_ combination: Combination, fullHandCount: Int) -> Int {
        if combination.cards.count == fullHandCount {
            return 50_000
        }

        var score = combination.cards.count * 260 - rankValue(combination.primaryRank) * 4
        switch combination.kind {
        case .singleRun:
            score += 900 + combination.sequenceLength * 90
        case .pairRun:
            score += 1_150 + combination.sequenceLength * 115
        case .sameRankBomb:
            score += 420 + combination.sameRankCount * 90
        case .triadWithSingle:
            score += fullHandCount <= 7 ? 420 : 60
        case .triadWithPair:
            score += fullHandCount <= 7 ? 520 : 80
        case .doubleJoker, .rocket414:
            score += 180
        case .single, .pair:
            score += rankValue(combination.primaryRank) <= Rank.ten.rawValue ? 90 : -120
        case .cha, .gou:
            break
        }
        return score
    }

    func searchPriority(_ cards: [Card], turns: Int) -> Int {
        let groups = Dictionary(grouping: cards, by: \.rank)
        let singletonCount = groups.values.filter { $0.count == 1 }.count
        return turns * 1_000 + cards.count * 40 + singletonCount * 95 - structureValue(cards) / 8
    }

    func handSignature(_ cards: [Card]) -> String {
        Rank.allCases.map { "\($0.rawValue):\(cards.count(of: $0))" }.joined(separator: "|")
    }

    func controlValue(_ cards: [Card]) -> Int {
        var value = cards.reduce(0) { partial, card in
            partial + (isControlCard(card) ? cardResourceValue(card) : 0)
        }
        if cards.containsRocket414() { value += 1_250 }
        if cards.containsDoubleJoker() { value += 920 }
        return value
    }

    func structureValue(_ cards: [Card]) -> Int {
        guard !cards.isEmpty else { return 0 }
        let groups = Dictionary(grouping: cards, by: \.rank)
        var value = 0

        for (rank, rankCards) in groups {
            switch rankCards.count {
            case 2:
                value += 120 + rank.rawValue * 4
            case 3:
                value += 520 + rank.rawValue * 8
            case 4...:
                value += 920 + rankCards.count * 155 + rank.rawValue * 12
            default:
                break
            }
        }

        if cards.containsRocket414() {
            value += 1_450
        }
        if cards.containsDoubleJoker() {
            value += 1_080
        }

        value += runStructureValue(groups: groups, repeatCount: 1, unit: 58)
        value += runStructureValue(groups: groups, repeatCount: 2, unit: 82)

        return value
    }

    func runStructureValue(groups: [Rank: [Card]], repeatCount: Int, unit: Int) -> Int {
        var best = 0
        var currentLength = 0

        for rank in Rank.runRanks {
            if (groups[rank]?.count ?? 0) >= repeatCount {
                currentLength += 1
                if currentLength >= 3 {
                    best = max(best, currentLength * currentLength * unit)
                }
            } else {
                currentLength = 0
            }
        }

        return best
    }

    func bestRunLength(groups: [Rank: [Card]], repeatCount: Int) -> Int {
        var best = 0
        var currentLength = 0

        for rank in Rank.runRanks {
            if (groups[rank]?.count ?? 0) >= repeatCount {
                currentLength += 1
                if currentLength >= 3 {
                    best = max(best, currentLength)
                }
            } else {
                currentLength = 0
            }
        }

        return best
    }

    func duplicateRanksUsed(by cards: [Card]) -> Int {
        Set(cards.map(\.rank)).filter { hand.count(of: $0) > 1 }.count
    }
}

private func aiTablePressure(state: GameState, playerIndex: Int) -> Int {
    let totalCards = max(1, state.deckCount * 54)
    let playedCards = min(totalCards, max(0, state.cardsPlayedCount.reduce(0, +)))
    let progressPressure = Int((Double(playedCards) / Double(totalCards)) * 42.0)

    let opponentCounts = state.hands.indices
        .filter { $0 != playerIndex }
        .map { state.hands[$0].count }
        .filter { $0 > 0 }
    let minOpponentCards = opponentCounts.min() ?? 99
    let remainingPressure = max(0, 72 - minOpponentCards * 8)

    var lastActorPressure = 0
    if let lastRecord = state.lastPlayableRecord,
       lastRecord.playerIndex != playerIndex,
       state.hands.indices.contains(lastRecord.playerIndex) {
        let remaining = state.hands[lastRecord.playerIndex].count
        if remaining > 0 {
            lastActorPressure = max(0, 42 - remaining * 6)
        }
    }

    let passPressure = state.prompt.kind == .follow ? state.passCount * 5 : 0
    return min(100, progressPressure + remainingPressure + lastActorPressure + passPressure)
}

private struct ThreatContext {
    let state: GameState
    let playerIndex: Int
    let threatPlayer: Int?
    let minimumThreatCards: Int?
    let threatPressure: Int
    let coverageStrength: Int
    let interceptReliabilityAfterMe: Int
    let defenseResponsibility: Int
    let currentControllerIsThreat: Bool

    init(state: GameState, playerIndex: Int) {
        self.state = state
        self.playerIndex = playerIndex

        let threats = state.hands.indices
            .filter { $0 != playerIndex }
            .compactMap { index -> (index: Int, count: Int)? in
                let count = state.hands[index].count
                return (1...3).contains(count) ? (index, count) : nil
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                if state.lastPlayableRecord?.playerIndex == lhs.index {
                    return true
                }
                if state.lastPlayableRecord?.playerIndex == rhs.index {
                    return false
                }
                return turnDistance(from: playerIndex, to: lhs.index, playerCount: state.players.count) <
                    turnDistance(from: playerIndex, to: rhs.index, playerCount: state.players.count)
            }

        guard let threat = threats.first else {
            self.threatPlayer = nil
            self.minimumThreatCards = nil
            self.threatPressure = 0
            self.coverageStrength = 0
            self.interceptReliabilityAfterMe = 0
            self.defenseResponsibility = 0
            self.currentControllerIsThreat = false
            return
        }

        self.threatPlayer = threat.index
        self.minimumThreatCards = threat.count

        let currentController = state.lastPlayableRecord?.playerIndex
        let currentCombination = state.lastPlayableRecord?.combination
        self.currentControllerIsThreat = currentController == threat.index
        let basePressure: Int
        switch threat.count {
        case 1:
            basePressure = 96
        case 2:
            basePressure = 82
        default:
            basePressure = 56
        }
        let controllerBonus = currentController == threat.index ? 18 : 0
        let leadBonus = state.prompt.kind == .lead && state.prompt.playerIndex == threat.index ? 12 : 0
        self.threatPressure = min(
            100,
            basePressure + controllerBonus + leadBonus + aiTablePressure(state: state, playerIndex: playerIndex) / 5
        )

        self.coverageStrength = Self.coverageStrength(
            threatCards: threat.count,
            threatPlayer: threat.index,
            currentController: currentController,
            currentCombination: currentCombination
        )
        self.interceptReliabilityAfterMe = Self.interceptReliabilityAfterMe(
            state: state,
            playerIndex: playerIndex,
            threatPlayer: threat.index,
            currentController: currentController,
            currentCombination: currentCombination
        )

        self.defenseResponsibility = self.threatPressure *
            max(0, 100 - self.coverageStrength) *
            max(0, 100 - self.interceptReliabilityAfterMe) / 10_000
    }

    static func coverageStrength(
        threatCards: Int,
        threatPlayer: Int,
        currentController: Int?,
        currentCombination: Combination?
    ) -> Int {
        guard let currentController,
              currentController != threatPlayer,
              let currentCombination
        else { return 0 }

        switch threatCards {
        case 1:
            return currentCombination.kind == .single ? 0 : 86
        case 2:
            if currentCombination.cards.count >= 3 {
                return 82
            }
            if currentCombination.kind == .pair || currentCombination.kind == .doubleJoker {
                return 36
            }
            return 0
        default:
            switch currentCombination.kind {
            case .singleRun:
                return 54 + min(18, currentCombination.sequenceLength * 3)
            case .pairRun:
                return 68 + min(16, currentCombination.sequenceLength * 3)
            case .triadWithSingle, .triadWithPair:
                return 68
            case .sameRankBomb, .doubleJoker, .rocket414:
                return 76
            case .pair:
                return 24
            case .single, .cha, .gou:
                return 0
            }
        }
    }

    static func interceptReliabilityAfterMe(
        state: GameState,
        playerIndex: Int,
        threatPlayer: Int,
        currentController: Int?,
        currentCombination: Combination?
    ) -> Int {
        guard state.prompt.kind == .follow,
              let currentController,
              state.players.indices.contains(currentController)
        else { return 0 }

        var combined = 0
        var next = (playerIndex + 1) % state.players.count
        while next != currentController {
            if next == threatPlayer {
                break
            }
            let reliability = playerReliability(
                state: state,
                playerIndex: playerIndex,
                candidateIndex: next,
                threatPlayer: threatPlayer,
                currentCombination: currentCombination
            )
            combined = 100 - ((100 - combined) * (100 - reliability) / 100)
            next = (next + 1) % state.players.count
        }
        return min(92, combined)
    }

    static func playerReliability(
        state: GameState,
        playerIndex: Int,
        candidateIndex: Int,
        threatPlayer: Int,
        currentCombination: Combination?
    ) -> Int {
        guard candidateIndex != threatPlayer,
              state.hands.indices.contains(candidateIndex)
        else { return 0 }

        let handCount = state.hands[candidateIndex].count
        guard handCount > 0 else { return 0 }

        var reliability: Int
        switch handCount {
        case 1...2:
            reliability = 10
        case 3...4:
            reliability = 24
        case 5...7:
            reliability = 42
        case 8...:
            reliability = 56
        default:
            reliability = 0
        }

        reliability += min(22, unseenControlCount(state: state, playerIndex: playerIndex) * 4)
        reliability -= combinationDifficulty(currentCombination)
        if handCount <= 2 {
            reliability -= 22
        }

        return min(85, max(0, reliability))
    }

    static func unseenControlCount(state: GameState, playerIndex: Int) -> Int {
        let total = state.deckCount * 6
        let visibleFromEvents = state.eventLog.reduce(0) { partial, record in
            partial + (record.combination?.cards.filter(isControlCard).count ?? 0)
        }
        let ownControls = state.hands.indices.contains(playerIndex) ?
            state.hands[playerIndex].filter(isControlCard).count : 0
        return max(0, total - visibleFromEvents - ownControls)
    }

    static func combinationDifficulty(_ combination: Combination?) -> Int {
        guard let combination else { return 0 }
        let rank = combination.primaryRank?.rawValue ?? 0
        switch combination.kind {
        case .single:
            return max(0, (rank - Rank.queen.rawValue) * 7)
        case .pair:
            return 14 + max(0, (rank - Rank.jack.rawValue) * 5)
        case .singleRun:
            return 18 + combination.sequenceLength * 3
        case .pairRun:
            return 38 + combination.sequenceLength * 4
        case .triadWithSingle, .triadWithPair:
            return 32
        case .sameRankBomb:
            return 68 + combination.sameRankCount * 4
        case .doubleJoker:
            return 84
        case .rocket414:
            return 96
        case .cha, .gou:
            return 48
        }
    }

    static func isControlCard(_ card: Card) -> Bool {
        card.rank == .two || card.rank == .smallJoker || card.rank == .bigJoker
    }
}

private func turnDistance(from start: Int, to end: Int, playerCount: Int) -> Int {
    guard playerCount > 0 else { return 0 }
    return (end - start + playerCount) % playerCount
}

private func blocksSingleCardOut(_ combination: Combination) -> Bool {
    switch combination.kind {
    case .pair,
         .sameRankBomb,
         .triadWithSingle,
         .triadWithPair,
         .singleRun,
         .pairRun,
         .doubleJoker,
         .rocket414:
        return true
    case .single, .cha, .gou:
        return false
    }
}

private func restrictiveShapeScore(_ combination: Combination) -> Int {
    switch combination.kind {
    case .single:
        return -280
    case .pair:
        return 120
    case .singleRun:
        return 320 + combination.sequenceLength * 55
    case .pairRun:
        return 500 + combination.sequenceLength * 65
    case .triadWithSingle:
        return 460
    case .triadWithPair:
        return 540
    case .sameRankBomb:
        return 360 + combination.sameRankCount * 45
    case .doubleJoker:
        return 420
    case .rocket414:
        return 500
    case .cha, .gou:
        return 0
    }
}

private struct PlanMetrics {
    let estimatedTurns: Int
    let singletonCount: Int
    let controlValue: Int
    let structureValue: Int
    let bestSingleRunLength: Int
    let bestPairRunLength: Int
}

private struct SearchNode {
    let cards: [Card]
    let turns: Int
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
}
