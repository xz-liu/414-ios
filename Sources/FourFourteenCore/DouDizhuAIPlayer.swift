import Foundation

public struct DouDizhuAIPlayer: Sendable {
    public init() {}

    public func chooseBid(state: DouDizhuState, for playerIndex: Int) -> DouDizhuBidAction {
        let legal = legalBidActions(from: state, for: playerIndex)
        guard !legal.isEmpty, state.hands.indices.contains(playerIndex) else { return .pass }

        let metrics = DouDizhuHandPlanMetrics(cards: state.hands[playerIndex])
        let score = metrics.bidScore
        let targetBid: Int
        if score >= 13 {
            targetBid = 3
        } else if score >= 7.2 {
            targetBid = 2
        } else if score >= 2.4 || shouldTakeFinalLowBid(state: state) {
            targetBid = 1
        } else {
            targetBid = 0
        }

        guard targetBid > state.highestBid else { return .pass }
        for value in stride(from: min(3, targetBid), through: state.highestBid + 1, by: -1) {
            let action = DouDizhuBidAction.bid(value)
            if legal.contains(action) {
                return action
            }
        }
        return .pass
    }

    private func shouldTakeFinalLowBid(state: DouDizhuState) -> Bool {
        state.highestBid == 0
            && state.bidTurnCount >= max(0, state.players.count - 1)
    }

    public func chooseAction(state: DouDizhuState, for playerIndex: Int) -> DouDizhuAction {
        let actions = legalPlayActions(from: state, for: playerIndex)
        guard !actions.isEmpty, state.hands.indices.contains(playerIndex) else { return .pass }

        let handCount = state.hands[playerIndex].count
        if let finish = actions.first(where: { !$0.cards.isEmpty && $0.cards.count == handCount }) {
            return finish
        }

        return DouDizhuActionEvaluator(state: state, playerIndex: playerIndex)
            .bestAction(from: actions)
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
        let previous = activePreviousCombination(in: state, for: playerIndex)
        let plays = DouDizhuRulesEngine.legalCombinations(in: state.hands[playerIndex], beating: previous)
            .map { DouDizhuAction.play($0.cards) }
        if previous == nil {
            return plays
        }
        return plays + [.pass]
    }

    private func activePreviousCombination(in state: DouDizhuState, for playerIndex: Int) -> DouDizhuCombination? {
        guard let lastPlay = state.lastPlay, lastPlay.playerIndex != playerIndex else { return nil }
        return lastPlay.combination
    }
}

private struct DouDizhuActionEvaluator {
    let state: DouDizhuState
    let playerIndex: Int
    let hand: [Card]
    let beforeMetrics: DouDizhuHandPlanMetrics
    let context: DouDizhuTeamContext

    init(state: DouDizhuState, playerIndex: Int) {
        self.state = state
        self.playerIndex = playerIndex
        self.hand = state.hands.indices.contains(playerIndex) ? state.hands[playerIndex] : []
        self.beforeMetrics = DouDizhuHandPlanMetrics(cards: hand)
        self.context = DouDizhuTeamContext(state: state, playerIndex: playerIndex)
    }

    func bestAction(from actions: [DouDizhuAction]) -> DouDizhuAction {
        actions
            .map { action in
                DouDizhuScoredAction(
                    action: action,
                    score: score(action),
                    tieBreaker: tieBreaker(for: action)
                )
            }
            .max { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                return lhs.tieBreaker < rhs.tieBreaker
            }?
            .action ?? .pass
    }

    private func score(_ action: DouDizhuAction) -> Double {
        switch action {
        case .pass:
            return passScore()
        case .play(let cards):
            guard let combination = DouDizhuRulesEngine.classify(cards) else { return -1_000_000 }
            let afterHand = hand.removing(cards)
            if afterHand.isEmpty {
                return 1_000_000 + Double(cards.count)
            }

            let afterMetrics = DouDizhuHandPlanMetrics(cards: afterHand)
            let turnDelta = beforeMetrics.estimatedTurns - afterMetrics.estimatedTurns
            var score = Double(turnDelta) * 920
            score += Double(cards.count) * 28
            score += shapeBenefit(for: combination, turnDelta: turnDelta, afterMetrics: afterMetrics)
            score += teamAdjustment(for: combination, cards: cards, afterMetrics: afterMetrics, turnDelta: turnDelta)
            score -= resourceCost(for: combination, cards: cards)
            score -= structureCost(for: combination, afterMetrics: afterMetrics)
            score -= overkillPenalty(for: combination)
            score -= nakedAirplanePenalty(for: combination, afterMetrics: afterMetrics, turnDelta: turnDelta)

            if afterMetrics.estimatedTurns <= 2 {
                score += Double(3 - afterMetrics.estimatedTurns) * 240
            }
            return score
        }
    }

    private func passScore() -> Double {
        guard context.isFollow else { return -1_000_000 }

        if context.previousIsTeammate {
            var score = 760.0
            if (context.teammateCardCount ?? 17) <= 4 {
                score += 760
            }
            if context.landlordIsShort, selfRunStrength > 0.72 {
                score -= 420
            }
            score -= context.teammateCoverageRisk * 3_000
            return score
        }

        if context.previousIsLandlord {
            return -620 - context.defenseResponsibility * 2_700
        }

        if context.isLandlord {
            return -360 - context.shortestFarmerPressure * 1_900
        }

        return -160
    }

    private func shapeBenefit(
        for combination: DouDizhuCombination,
        turnDelta: Int,
        afterMetrics: DouDizhuHandPlanMetrics
    ) -> Double {
        switch combination.kind {
        case .single:
            return combination.primaryRank.rawValue <= Rank.ten.rawValue ? 130 : 20
        case .pair:
            return combination.primaryRank.rawValue <= Rank.jack.rawValue ? 190 : 80
        case .trio:
            return 120
        case .trioWithSingle:
            return 380
        case .trioWithPair:
            return 460
        case .singleStraight:
            return 520 + Double(combination.sequenceLength) * 44
        case .pairStraight:
            return 640 + Double(combination.sequenceLength) * 52
        case .airplane:
            if turnDelta >= 2 || afterMetrics.estimatedTurns <= 2 {
                return 520 + Double(combination.sequenceLength) * 58
            }
            return -260
        case .airplaneWithSingles:
            return 760 + Double(combination.sequenceLength) * 72
        case .airplaneWithPairs:
            return 820 + Double(combination.sequenceLength) * 78
        case .fourWithTwoSingles:
            return 110
        case .fourWithTwoPairs:
            return 170
        case .bomb:
            return context.defenseResponsibility * 1_200
        case .rocket:
            return context.defenseResponsibility * 1_500
        }
    }

    private func teamAdjustment(
        for combination: DouDizhuCombination,
        cards: [Card],
        afterMetrics: DouDizhuHandPlanMetrics,
        turnDelta: Int
    ) -> Double {
        if context.previousIsTeammate {
            var score = -2_250.0
            if (context.teammateCardCount ?? 17) <= 4 {
                score -= 900
            }
            score += context.teammateCoverageRisk * 9_000
            if combination.isBombLike {
                score -= 2_000
            }
            if selfRunStrength > 0.72, afterMetrics.estimatedTurns <= 2 {
                score += 1_800
            }
            if selfRunStrength > 0.66, turnDelta >= 2 {
                score += 1_120
            }
            if context.landlordIsShort {
                score += 360
            }
            return score
        }

        if context.previousIsLandlord {
            var score = 560 + context.defenseResponsibility * 2_850
            if context.landlordIsShort {
                score += 1_200
            } else if context.landlordIsNear {
                score += 430
            }
            if !combination.isBombLike {
                score += context.defenseResponsibility * 360
            }
            return score
        }

        if context.isLandlord, context.isFollow {
            return 420 + context.shortestFarmerPressure * 2_150
        }

        if context.isLead {
            return leadThreatAdjustment(for: combination, cards: cards)
        }

        return 0
    }

    private func leadThreatAdjustment(for combination: DouDizhuCombination, cards: [Card]) -> Double {
        if context.isLandlord {
            if context.shortestFarmerCardCount <= 2 {
                return combination.cards.count >= 3 ? 760 : -520
            }
            return selfRunStrength > 0.66 ? 260 : 0
        }

        guard let landlordCount = context.landlordCardCount else { return 0 }
        if landlordCount == 1 {
            switch combination.kind {
            case .single:
                return -980
            case .pair, .trio, .trioWithSingle, .trioWithPair,
                 .singleStraight, .pairStraight, .airplane, .airplaneWithSingles,
                 .airplaneWithPairs, .fourWithTwoSingles, .fourWithTwoPairs:
                return 980
            case .bomb, .rocket:
                return 320
            }
        }
        if landlordCount == 2 {
            if cards.count >= 3 {
                return 720
            }
            if combination.kind == .pair {
                return 260
            }
            if combination.kind == .single {
                return -360
            }
        }
        if selfRunStrength > 0.72 {
            return 280
        }
        return 0
    }

    private func resourceCost(for combination: DouDizhuCombination, cards: [Card]) -> Double {
        var cost = cards.reduce(0.0) { $0 + DouDizhuHandPlanMetrics.controlCost(for: $1.rank) }
        switch combination.kind {
        case .bomb:
            cost += 1_650 + Double(combination.primaryRank.rawValue) * 32
        case .rocket:
            cost += 2_700
        case .fourWithTwoSingles, .fourWithTwoPairs:
            cost += 820
        case .pair where combination.primaryRank == .two:
            cost += 420
        case .single where combination.primaryRank == .two:
            cost += 250
        default:
            break
        }

        if context.previousIsLandlord {
            let discount = min(0.62, context.defenseResponsibility * 0.58 + (context.landlordIsShort ? 0.18 : 0))
            cost *= 1 - discount
        } else if context.previousIsTeammate, context.teammateCoverageRisk > 0 {
            cost *= 1 - min(0.68, context.teammateCoverageRisk * 0.70)
        } else if context.isLandlord, context.shortestFarmerCardCount <= 2 {
            cost *= 0.78
        }
        return cost
    }

    private func structureCost(for combination: DouDizhuCombination, afterMetrics: DouDizhuHandPlanMetrics) -> Double {
        let rawLoss = max(0, beforeMetrics.structureValue - afterMetrics.structureValue)
        guard rawLoss > 0 else { return 0 }

        switch combination.kind {
        case .singleStraight, .pairStraight, .airplaneWithSingles, .airplaneWithPairs:
            return rawLoss * 0.18
        case .trioWithSingle, .trioWithPair:
            return rawLoss * 0.42
        case .airplane:
            return rawLoss * 0.34
        case .bomb, .rocket:
            return rawLoss * 0.72
        case .single, .pair:
            return rawLoss * 1.08
        default:
            return rawLoss * 0.62
        }
    }

    private func overkillPenalty(for combination: DouDizhuCombination) -> Double {
        guard context.isFollow,
              let previous = context.previousCombination,
              !previous.isBombLike
        else { return 0 }

        var penalty = 0.0
        if combination.kind == .bomb {
            penalty += 1_250
        } else if combination.kind == .rocket {
            penalty += 1_850
        }

        let lowValueTarget = previous.primaryRank.rawValue <= Rank.jack.rawValue
        if lowValueTarget, context.defenseResponsibility < 0.62 {
            if combination.primaryRank == .two {
                penalty += 620
            }
            if combination.primaryRank == .smallJoker || combination.primaryRank == .bigJoker {
                penalty += 820
            }
        }
        if context.previousIsTeammate {
            penalty += 520 * (1 - context.teammateCoverageRisk)
        }
        return penalty
    }

    private func nakedAirplanePenalty(
        for combination: DouDizhuCombination,
        afterMetrics: DouDizhuHandPlanMetrics,
        turnDelta: Int
    ) -> Double {
        guard combination.kind == .airplane,
              !hand.removing(combination.cards).isEmpty,
              turnDelta < 2,
              afterMetrics.estimatedTurns > 2
        else { return 0 }

        return hasWingedAirplaneAlternative(to: combination) ? 4_200 : 1_250
    }

    private func hasWingedAirplaneAlternative(to combination: DouDizhuCombination) -> Bool {
        DouDizhuRulesEngine.legalCombinations(in: hand).contains { candidate in
            (candidate.kind == .airplaneWithSingles || candidate.kind == .airplaneWithPairs)
                && candidate.primaryRank == combination.primaryRank
                && candidate.sequenceLength == combination.sequenceLength
        }
    }

    private func tieBreaker(for action: DouDizhuAction) -> Double {
        switch action {
        case .pass:
            return -10
        case .play(let cards):
            guard let combination = DouDizhuRulesEngine.classify(cards) else { return -1_000_000 }
            let resource = resourceCost(for: combination, cards: cards)
            return -resource - Double(DouDizhuRulesEngine.combinationSortScore(combination)) / 10_000
        }
    }

    private var selfRunStrength: Double {
        beforeMetrics.runStrength
    }
}

private struct DouDizhuScoredAction {
    let action: DouDizhuAction
    let score: Double
    let tieBreaker: Double
}

private struct DouDizhuTeamContext {
    let state: DouDizhuState
    let playerIndex: Int
    let landlordIndex: Int?
    let previousPlayerIndex: Int?
    let previousCombination: DouDizhuCombination?

    init(state: DouDizhuState, playerIndex: Int) {
        self.state = state
        self.playerIndex = playerIndex
        self.landlordIndex = state.landlordIndex
        if let lastPlay = state.lastPlay, lastPlay.playerIndex != playerIndex {
            self.previousPlayerIndex = lastPlay.playerIndex
            self.previousCombination = lastPlay.combination
        } else {
            self.previousPlayerIndex = nil
            self.previousCombination = nil
        }
    }

    var isLandlord: Bool {
        playerIndex == landlordIndex
    }

    var isFollow: Bool {
        previousCombination != nil
    }

    var isLead: Bool {
        !isFollow
    }

    var previousIsLandlord: Bool {
        previousPlayerIndex == landlordIndex
    }

    var previousIsTeammate: Bool {
        guard let landlordIndex,
              let previousPlayerIndex,
              playerIndex != landlordIndex,
              previousPlayerIndex != landlordIndex
        else { return false }
        return previousPlayerIndex != playerIndex
    }

    var teammateIndex: Int? {
        guard let landlordIndex, playerIndex != landlordIndex else { return nil }
        return state.players.indices.first { $0 != playerIndex && $0 != landlordIndex }
    }

    var teammateCardCount: Int? {
        teammateIndex.flatMap { index in state.hands.indices.contains(index) ? state.hands[index].count : nil }
    }

    var teammateCoverageRisk: Double {
        guard previousIsTeammate,
              let landlordIndex,
              nextIndex(after: playerIndex) == landlordIndex,
              let landlordCount = landlordCardCount,
              landlordCount <= 5,
              let previousCombination
        else { return 0 }

        let pressure: Double
        switch landlordCount {
        case 0...1:
            pressure = 1.0
        case 2:
            pressure = 0.92
        case 3:
            pressure = 0.78
        case 4:
            pressure = 0.62
        default:
            pressure = 0.48
        }

        let shapeRisk: Double
        switch previousCombination.kind {
        case .single:
            shapeRisk = 1.0
        case .pair:
            shapeRisk = 0.72
        case .trio, .trioWithSingle, .trioWithPair:
            shapeRisk = 0.45
        case .singleStraight, .pairStraight, .airplane, .airplaneWithSingles, .airplaneWithPairs:
            shapeRisk = 0.28
        case .fourWithTwoSingles, .fourWithTwoPairs:
            shapeRisk = 0.22
        case .bomb, .rocket:
            shapeRisk = 0.04
        }

        let rankRisk: Double
        if previousCombination.primaryRank == .bigJoker {
            rankRisk = 0.02
        } else if previousCombination.primaryRank == .smallJoker {
            rankRisk = 0.18
        } else if previousCombination.primaryRank == .two {
            rankRisk = 0.34
        } else if previousCombination.primaryRank == .ace {
            rankRisk = 0.80
        } else if previousCombination.primaryRank.rawValue >= Rank.jack.rawValue {
            rankRisk = 0.92
        } else {
            rankRisk = 1.0
        }

        return min(1, pressure * shapeRisk * rankRisk)
    }

    var landlordCardCount: Int? {
        landlordIndex.flatMap { index in state.hands.indices.contains(index) ? state.hands[index].count : nil }
    }

    var landlordIsShort: Bool {
        (landlordCardCount ?? 99) <= 2
    }

    var landlordIsNear: Bool {
        (landlordCardCount ?? 99) <= 5
    }

    var shortestFarmerCardCount: Int {
        guard let landlordIndex else { return 99 }
        return state.players.indices
            .filter { $0 != landlordIndex }
            .compactMap { state.hands.indices.contains($0) ? state.hands[$0].count : nil }
            .min() ?? 99
    }

    var shortestFarmerPressure: Double {
        pressure(forRemainingCards: shortestFarmerCardCount)
    }

    var defenseResponsibility: Double {
        if previousIsTeammate {
            return 0
        }

        let pressure = isLandlord ? shortestFarmerPressure : pressure(forRemainingCards: landlordCardCount ?? 99)
        let coverage = previousIsLandlord ? 0 : coverageStrength
        let reliability = interceptReliabilityAfterMe
        return max(0, min(1, pressure * (1 - coverage) * (1 - reliability)))
    }

    var coverageStrength: Double {
        guard let previousCombination else { return 0 }
        switch previousCombination.kind {
        case .single:
            return 0.05
        case .pair:
            return 0.18
        case .trio, .trioWithSingle, .trioWithPair:
            return 0.34
        case .singleStraight, .pairStraight, .airplane, .airplaneWithSingles, .airplaneWithPairs:
            return 0.48
        case .fourWithTwoSingles, .fourWithTwoPairs:
            return 0.44
        case .bomb, .rocket:
            return 0.72
        }
    }

    var interceptReliabilityAfterMe: Double {
        guard isFollow, let previousPlayerIndex else { return 0 }
        var best = 0.0
        var index = nextIndex(after: playerIndex)
        var visited = 0
        while index != previousPlayerIndex, visited < state.players.count - 1 {
            best = max(best, estimatedReliability(ofPlayerAt: index))
            index = nextIndex(after: index)
            visited += 1
        }
        return min(0.86, best)
    }

    private func estimatedReliability(ofPlayerAt index: Int) -> Double {
        guard state.hands.indices.contains(index) else { return 0 }
        if index == landlordIndex, !isLandlord {
            return 0
        }
        if let landlordIndex, playerIndex == landlordIndex, index == landlordIndex {
            return 0
        }

        let cardCount = state.hands[index].count
        var reliability: Double
        switch cardCount {
        case 0...1:
            reliability = 0.04
        case 2:
            reliability = 0.10
        case 3...5:
            reliability = 0.25
        case 6...10:
            reliability = 0.42
        default:
            reliability = 0.55
        }

        if let previousCombination {
            switch previousCombination.kind {
            case .bomb:
                reliability *= 0.36
            case .rocket:
                reliability = 0
            case .single where previousCombination.primaryRank.rawValue >= Rank.two.rawValue:
                reliability *= 0.55
            case .pair where previousCombination.primaryRank.rawValue >= Rank.ace.rawValue:
                reliability *= 0.62
            case .singleStraight, .pairStraight, .airplane, .airplaneWithSingles, .airplaneWithPairs:
                reliability *= 0.78
            default:
                break
            }
        }
        return reliability
    }

    private func pressure(forRemainingCards count: Int) -> Double {
        switch count {
        case 0...1:
            return 1.0
        case 2:
            return 0.86
        case 3:
            return 0.66
        case 4...5:
            return 0.42
        case 6...8:
            return 0.24
        default:
            return 0.12
        }
    }

    private func nextIndex(after index: Int) -> Int {
        guard !state.players.isEmpty else { return index }
        return (index + 1) % state.players.count
    }
}

private struct DouDizhuHandPlanMetrics {
    let cardCount: Int
    let estimatedTurns: Int
    let singletonCount: Int
    let controlValue: Double
    let structureValue: Double
    let bombCount: Int
    let hasRocket: Bool
    let bestStraightLength: Int
    let bestPairStraightLength: Int

    init(cards: [Card]) {
        let cards = cards.sortedForHand()
        let groups = Dictionary(grouping: cards, by: \.rank)
        self.cardCount = cards.count
        self.singletonCount = groups.values.filter { $0.count == 1 }.count
        self.bombCount = groups.filter { rank, cards in
            rank != .smallJoker && rank != .bigJoker && cards.count >= 4
        }.count
        self.hasRocket = cards.containsDoubleJoker()
        self.bestStraightLength = Self.longestChain(in: groups, requiredCount: 1)
        self.bestPairStraightLength = Self.longestChain(in: groups, requiredCount: 2)
        self.controlValue = Self.computeControlValue(cards: cards, groups: groups, bombCount: bombCount, hasRocket: hasRocket)
        self.structureValue = Self.computeStructureValue(groups: groups, singletonCount: singletonCount, bombCount: bombCount)
        self.estimatedTurns = Self.estimateTurns(cards: cards)
    }

    var runStrength: Double {
        let turnComponent = min(1, max(0, Double(8 - estimatedTurns)) / 7)
        let controlComponent = min(1, controlValue / 155)
        let structureComponent = min(1, max(0, structureValue) / 130)
        return min(1, turnComponent * 0.46 + controlComponent * 0.32 + structureComponent * 0.22)
    }

    var bidScore: Double {
        controlValue / 7.2
            + structureValue / 9.0
            + Double(bombCount) * 4.2
            + (hasRocket ? 6.0 : 0)
            - Double(estimatedTurns) * 1.45
            - Double(singletonCount) * 0.75
    }

    static func controlCost(for rank: Rank) -> Double {
        switch rank {
        case .bigJoker:
            return 900
        case .smallJoker:
            return 700
        case .two:
            return 430
        case .ace:
            return 130
        case .king:
            return 72
        case .queen:
            return 44
        case .jack:
            return 24
        default:
            return 0
        }
    }

    private static func computeControlValue(
        cards: [Card],
        groups: [Rank: [Card]],
        bombCount: Int,
        hasRocket: Bool
    ) -> Double {
        var value = cards.reduce(0.0) { result, card in
            switch card.rank {
            case .bigJoker:
                return result + 32
            case .smallJoker:
                return result + 27
            case .two:
                return result + 16
            case .ace:
                return result + 7
            case .king:
                return result + 4
            case .queen:
                return result + 2
            default:
                return result
            }
        }
        value += Double(bombCount) * 32
        if hasRocket {
            value += 48
        }
        for (rank, rankCards) in groups where rankCards.count == 3 && rank.rawValue >= Rank.queen.rawValue {
            value += 5
        }
        return value
    }

    private static func computeStructureValue(
        groups: [Rank: [Card]],
        singletonCount: Int,
        bombCount: Int
    ) -> Double {
        let trioCount = groups.filter { rank, cards in
            rank != .smallJoker && rank != .bigJoker && cards.count >= 3
        }.count
        let trioChain = longestChain(in: groups, requiredCount: 3)
        var value = Double(trioCount) * 12
        value += Double(bombCount) * 18
        value += Double(max(0, longestChain(in: groups, requiredCount: 1) - 4)) * 8
        value += Double(max(0, longestChain(in: groups, requiredCount: 2) - 2)) * 12
        value += Double(max(0, trioChain - 1)) * 18
        value -= Double(singletonCount) * 2.5
        return value
    }

    private static func estimateTurns(cards: [Card]) -> Int {
        var remaining = cards.sortedForHand()
        var turns = 0
        var safety = 0

        while !remaining.isEmpty, safety < 36 {
            if DouDizhuRulesEngine.classify(remaining) != nil {
                return turns + 1
            }
            let candidates = DouDizhuRulesEngine.legalCombinations(in: remaining)
            guard let best = candidates.max(by: {
                planningScore(for: $0, remainingCount: remaining.count)
                    < planningScore(for: $1, remainingCount: remaining.count)
            }) else {
                return turns + remaining.count
            }
            remaining = remaining.removing(best.cards)
            turns += 1
            safety += 1
        }

        return turns + remaining.count
    }

    private static func planningScore(for combination: DouDizhuCombination, remainingCount: Int) -> Double {
        if combination.cards.count == remainingCount {
            return 100_000
        }

        var score = Double(combination.cards.count) * 100
        switch combination.kind {
        case .singleStraight:
            score += 760 + Double(combination.sequenceLength) * 34
        case .pairStraight:
            score += 840 + Double(combination.sequenceLength) * 42
        case .airplaneWithSingles:
            score += 960 + Double(combination.sequenceLength) * 58
        case .airplaneWithPairs:
            score += 1_020 + Double(combination.sequenceLength) * 66
        case .trioWithSingle:
            score += 520
        case .trioWithPair:
            score += 610
        case .airplane:
            score += 260
        case .trio:
            score += 250
        case .pair:
            score += 170
        case .single:
            score += 80
        case .fourWithTwoSingles, .fourWithTwoPairs:
            score -= 180
        case .bomb:
            score -= 760
        case .rocket:
            score -= 980
        }

        let controlSpend = combination.cards.reduce(0.0) { $0 + controlCost(for: $1.rank) }
        score -= controlSpend * 0.16
        return score
    }

    private static func longestChain(in groups: [Rank: [Card]], requiredCount: Int) -> Int {
        var current = 0
        var best = 0
        for rank in Rank.runRanks {
            if (groups[rank]?.count ?? 0) >= requiredCount {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
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
}
