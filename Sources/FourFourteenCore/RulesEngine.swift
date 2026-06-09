import Foundation

public enum RulesEngine {
    public static func classify(_ cards: [Card]) -> Combination? {
        let cards = cards.sortedForHand()
        guard !cards.isEmpty else { return nil }

        if let rocket = classifyRocket414(cards) {
            return rocket
        }
        if let doubleJoker = classifyDoubleJoker(cards) {
            return doubleJoker
        }
        if let sameRank = classifySameRank(cards) {
            return sameRank
        }
        if let triadWith = classifyTriadWith(cards) {
            return triadWith
        }
        if let run = classifyRun(cards) {
            return run
        }
        return nil
    }

    public static func canBeat(_ challenger: Combination, _ previous: Combination) -> Bool {
        guard challenger.kind != .cha && challenger.kind != .gou else { return false }
        guard previous.kind != .cha && previous.kind != .gou else { return false }

        if challenger.kind == .rocket414 {
            return previous.kind != .rocket414
        }
        if previous.kind == .rocket414 {
            return false
        }

        if challenger.kind == .doubleJoker {
            return previous.kind != .doubleJoker
        }
        if previous.kind == .doubleJoker {
            return false
        }

        if challenger.kind == .sameRankBomb && previous.kind == .sameRankBomb {
            if challenger.sameRankCount != previous.sameRankCount {
                return challenger.sameRankCount > previous.sameRankCount
            }
            return rankValue(challenger.primaryRank) > rankValue(previous.primaryRank)
        }

        if challenger.kind == .sameRankBomb && !previous.isBombLike {
            return canSameRankBombBeatOrdinary(challenger, previous)
        }
        if challenger.isBombLike && !previous.isBombLike {
            return true
        }
        if previous.isBombLike && !challenger.isBombLike {
            return false
        }

        guard challenger.kind == previous.kind else { return false }

        switch challenger.kind {
        case .single, .pair, .triadWithSingle, .triadWithPair:
            return rankValue(challenger.primaryRank) > rankValue(previous.primaryRank)
        case .singleRun, .pairRun:
            guard challenger.sequenceLength == previous.sequenceLength else { return false }
            return rankValue(challenger.primaryRank) > rankValue(previous.primaryRank)
        case .sameRankBomb, .doubleJoker, .rocket414, .cha, .gou:
            return false
        }
    }

    public static func legalCombinations(in hand: [Card], beating previous: Combination? = nil) -> [Combination] {
        let all = allCombinations(in: hand)
        guard let previous else { return all.sortedForDecision() }
        return all.filter { canBeat($0, previous) }.sortedForDecision()
    }

    public static func legalChaCards(in hand: [Card], rank: Rank) -> [Card]? {
        let cards = hand.sortedForHand().filter { $0.rank == rank }
        guard cards.count >= 2 else { return nil }
        return Array(cards.prefix(2))
    }

    public static func legalGouCard(in hand: [Card], rank: Rank) -> Card? {
        hand.sortedForHand().first { $0.rank == rank }
    }

    public static func combinationSortScore(_ combination: Combination) -> Int {
        let rank = rankValue(combination.primaryRank)
        switch combination.kind {
        case .single:
            return 100 + rank
        case .pair:
            return 200 + rank
        case .triadWithSingle:
            return 300 + rank
        case .triadWithPair:
            return 350 + rank
        case .singleRun:
            return 400 + combination.sequenceLength * 20 + rank
        case .pairRun:
            return 600 + combination.sequenceLength * 20 + rank
        case .sameRankBomb:
            return 10_000 + combination.sameRankCount * 100 + rank
        case .doubleJoker:
            return 90_000
        case .rocket414:
            return 100_000
        case .cha:
            return 95_000 + rank
        case .gou:
            return 96_000 + rank
        }
    }
}

private extension RulesEngine {
    static func classifyRocket414(_ cards: [Card]) -> Combination? {
        guard cards.count == 3 else { return nil }
        guard cards.count(of: .four) == 2 && cards.count(of: .ace) == 1 else { return nil }
        return Combination(kind: .rocket414, cards: cards, primaryRank: .ace)
    }

    static func canSameRankBombBeatOrdinary(_ bomb: Combination, _ previous: Combination) -> Bool {
        guard bomb.kind == .sameRankBomb else { return false }
        switch previous.kind {
        case .single, .pair:
            return true
        case .singleRun:
            return true
        case .triadWithSingle, .triadWithPair, .pairRun:
            return bomb.sameRankCount >= 4
        case .sameRankBomb, .doubleJoker, .rocket414, .cha, .gou:
            return false
        }
    }

    static func classifyDoubleJoker(_ cards: [Card]) -> Combination? {
        guard cards.count == 2 else { return nil }
        guard cards.count(of: .smallJoker) == 1 && cards.count(of: .bigJoker) == 1 else { return nil }
        return Combination(kind: .doubleJoker, cards: cards, primaryRank: .bigJoker)
    }

    static func classifySameRank(_ cards: [Card]) -> Combination? {
        guard let rank = cards.first?.rank else { return nil }
        guard cards.allSatisfy({ $0.rank == rank }) else { return nil }

        switch cards.count {
        case 1:
            return Combination(kind: .single, cards: cards, primaryRank: rank, sameRankCount: 1)
        case 2:
            return Combination(kind: .pair, cards: cards, primaryRank: rank, sameRankCount: 2)
        default:
            return Combination(kind: .sameRankBomb, cards: cards, primaryRank: rank, sameRankCount: cards.count)
        }
    }

    static func classifyTriadWith(_ cards: [Card]) -> Combination? {
        guard cards.count == 4 || cards.count == 5 else { return nil }
        let groups = Dictionary(grouping: cards, by: \.rank)
        guard groups.count == 2 else { return nil }
        guard let triad = groups.first(where: { $0.value.count == 3 }) else { return nil }
        let attachmentCount = cards.count - 3
        if attachmentCount == 2 {
            guard groups.contains(where: { $0.key != triad.key && $0.value.count == 2 }) else { return nil }
            return Combination(kind: .triadWithPair, cards: cards, primaryRank: triad.key, sameRankCount: 3)
        }
        return Combination(kind: .triadWithSingle, cards: cards, primaryRank: triad.key, sameRankCount: 3)
    }

    static func classifyRun(_ cards: [Card]) -> Combination? {
        guard cards.count >= 3 else { return nil }
        guard cards.allSatisfy({ $0.rank.canBeInRun }) else { return nil }

        let groups = Dictionary(grouping: cards, by: \.rank)
        let counts = Set(groups.values.map(\.count))
        guard counts.count == 1, let repeatCount = counts.first else { return nil }
        guard repeatCount == 1 || repeatCount == 2 else { return nil }

        let ranks = groups.keys.sorted()
        guard ranks.count >= 3 else { return nil }
        for index in 1..<ranks.count {
            guard ranks[index].rawValue == ranks[index - 1].rawValue + 1 else { return nil }
        }

        let kind: CombinationKind = repeatCount == 1 ? .singleRun : .pairRun
        return Combination(
            kind: kind,
            cards: cards,
            primaryRank: ranks.first,
            sameRankCount: repeatCount,
            sequenceLength: ranks.count
        )
    }

    static func allCombinations(in hand: [Card]) -> [Combination] {
        let hand = hand.sortedForHand()
        let groups = Dictionary(grouping: hand, by: \.rank)
            .mapValues { $0.sortedForHand() }
        var combinations: [Combination] = []

        for (_, cards) in groups {
            if let single = cards.first.flatMap({ classify([$0]) }) {
                combinations.append(single)
            }
            if cards.count >= 2, let pair = classify(Array(cards.prefix(2))) {
                combinations.append(pair)
            }
            if cards.count >= 3 {
                for count in 3...cards.count {
                    if let bomb = classify(Array(cards.prefix(count))) {
                        combinations.append(bomb)
                    }
                }
            }
        }

        if let fours = groups[.four], let aces = groups[.ace], fours.count >= 2, let ace = aces.first {
            combinations.append(
                Combination(kind: .rocket414, cards: Array(fours.prefix(2)) + [ace], primaryRank: .ace)
            )
        }

        if let small = groups[.smallJoker]?.first, let big = groups[.bigJoker]?.first {
            combinations.append(Combination(kind: .doubleJoker, cards: [small, big], primaryRank: .bigJoker))
        }

        for (rank, cards) in groups where cards.count >= 3 {
            let triad = Array(cards.prefix(3))
            for (attachmentRank, attachmentCards) in groups where attachmentRank != rank {
                if let card = attachmentCards.first,
                   let combo = classify(triad + [card]) {
                    combinations.append(combo)
                }
                if attachmentCards.count >= 2,
                   let combo = classify(triad + Array(attachmentCards.prefix(2))) {
                    combinations.append(combo)
                }
            }
        }

        combinations.append(contentsOf: runCombinations(groups: groups, repeatCount: 1))
        combinations.append(contentsOf: runCombinations(groups: groups, repeatCount: 2))

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

    static func runCombinations(groups: [Rank: [Card]], repeatCount: Int) -> [Combination] {
        let ranks = Rank.runRanks
        var combinations: [Combination] = []

        for startIndex in ranks.indices {
            var endIndex = startIndex
            while endIndex < ranks.count, (groups[ranks[endIndex]]?.count ?? 0) >= repeatCount {
                let length = endIndex - startIndex + 1
                if length >= 3 {
                    let rangeRanks = ranks[startIndex...endIndex]
                    let cards = rangeRanks.flatMap { rank in
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

    static func rankValue(_ rank: Rank?) -> Int {
        rank?.rawValue ?? -1
    }
}

private extension Array where Element == Combination {
    func sortedForDecision() -> [Combination] {
        sorted {
            let lhsScore = RulesEngine.combinationSortScore($0)
            let rhsScore = RulesEngine.combinationSortScore($1)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return $0.cards.count < $1.cards.count
        }
    }
}
