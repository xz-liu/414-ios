import Foundation

public enum DouDizhuRulesEngine {
    public static func classify(_ cards: [Card]) -> DouDizhuCombination? {
        let cards = cards.sortedForHand()
        guard !cards.isEmpty else { return nil }

        if let rocket = classifyRocket(cards) {
            return rocket
        }
        if let sameRank = classifySimpleSameRank(cards) {
            return sameRank
        }
        if let trioAttachment = classifyTrioAttachment(cards) {
            return trioAttachment
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
        if let fourWithTwo = classifyFourWithTwo(cards) {
            return fourWithTwo
        }
        return nil
    }

    public static func canBeat(_ challenger: DouDizhuCombination, _ previous: DouDizhuCombination) -> Bool {
        if challenger.kind == .rocket {
            return previous.kind != .rocket
        }
        if previous.kind == .rocket {
            return false
        }
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

    public static func legalCombinations(in hand: [Card], beating previous: DouDizhuCombination? = nil) -> [DouDizhuCombination] {
        let all = allCombinations(in: hand)
        let filtered = previous.map { previous in
            all.filter { canBeat($0, previous) }
        } ?? all
        return filtered.sortedForDouDizhuDecision()
    }

    public static func combinationSortScore(_ combination: DouDizhuCombination) -> Int {
        let rank = combination.primaryRank.rawValue
        switch combination.kind {
        case .single:
            return 100 + rank
        case .pair:
            return 200 + rank
        case .trio:
            return 300 + rank
        case .trioWithSingle:
            return 390 + rank
        case .trioWithPair:
            return 430 + rank
        case .singleStraight:
            return 1_000 + combination.sequenceLength * 20 + rank
        case .pairStraight:
            return 1_300 + combination.sequenceLength * 22 + rank
        case .airplane:
            return 1_600 + combination.sequenceLength * 28 + rank
        case .airplaneWithSingles:
            return 1_780 + combination.sequenceLength * 30 + rank
        case .airplaneWithPairs:
            return 1_900 + combination.sequenceLength * 32 + rank
        case .fourWithTwoSingles:
            return 2_000 + rank
        case .fourWithTwoPairs:
            return 2_100 + rank
        case .bomb:
            return 10_000 + rank
        case .rocket:
            return 20_000
        }
    }
}

private extension DouDizhuRulesEngine {
    static func classifyRocket(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count == 2,
              cards.count(of: .smallJoker) == 1,
              cards.count(of: .bigJoker) == 1
        else { return nil }
        return DouDizhuCombination(kind: .rocket, cards: cards, primaryRank: .bigJoker)
    }

    static func classifySimpleSameRank(_ cards: [Card]) -> DouDizhuCombination? {
        guard let rank = cards.first?.rank,
              cards.allSatisfy({ $0.rank == rank })
        else { return nil }

        switch cards.count {
        case 1:
            return DouDizhuCombination(kind: .single, cards: cards, primaryRank: rank)
        case 2:
            guard rank != .smallJoker, rank != .bigJoker else { return nil }
            return DouDizhuCombination(kind: .pair, cards: cards, primaryRank: rank)
        case 3:
            guard rank != .smallJoker, rank != .bigJoker else { return nil }
            return DouDizhuCombination(kind: .trio, cards: cards, primaryRank: rank)
        case 4:
            guard rank != .smallJoker, rank != .bigJoker else { return nil }
            return DouDizhuCombination(kind: .bomb, cards: cards, primaryRank: rank)
        default:
            return nil
        }
    }

    static func classifyTrioAttachment(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count == 4 || cards.count == 5 else { return nil }
        let groups = rankGroups(cards)
        guard let trio = groups.first(where: { $0.value.count == 3 }) else { return nil }
        let attachmentCards = cards.filter { $0.rank != trio.key }
        if cards.count == 4, attachmentCards.count == 1 {
            return DouDizhuCombination(kind: .trioWithSingle, cards: cards, primaryRank: trio.key)
        }
        if cards.count == 5,
           attachmentCards.count == 2,
           attachmentCards[0].rank == attachmentCards[1].rank {
            return DouDizhuCombination(kind: .trioWithPair, cards: cards, primaryRank: trio.key)
        }
        return nil
    }

    static func classifySingleStraight(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count >= 5,
              cards.allSatisfy({ $0.rank.canBeInDouDizhuChain })
        else { return nil }
        let ranks = cards.map(\.rank)
        guard Set(ranks).count == ranks.count,
              ranks.areConsecutive
        else { return nil }
        return DouDizhuCombination(
            kind: .singleStraight,
            cards: cards,
            primaryRank: ranks.max() ?? .three,
            sequenceLength: ranks.count
        )
    }

    static func classifyPairStraight(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count >= 6, cards.count.isMultiple(of: 2) else { return nil }
        let groups = rankGroups(cards)
        guard groups.count >= 3,
              groups.values.allSatisfy({ $0.count == 2 }),
              groups.keys.allSatisfy(\.canBeInDouDizhuChain)
        else { return nil }
        let ranks = groups.keys.sorted()
        guard ranks.areConsecutive else { return nil }
        return DouDizhuCombination(
            kind: .pairStraight,
            cards: cards,
            primaryRank: ranks.max() ?? .three,
            sequenceLength: ranks.count
        )
    }

    static func classifyAirplane(_ cards: [Card]) -> DouDizhuCombination? {
        if let bare = classifyBareAirplane(cards) {
            return bare
        }
        if let singles = classifyAirplaneWithSingles(cards) {
            return singles
        }
        return classifyAirplaneWithPairs(cards)
    }

    static func classifyBareAirplane(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count >= 6, cards.count.isMultiple(of: 3) else { return nil }
        let groups = rankGroups(cards)
        guard groups.count >= 2,
              groups.values.allSatisfy({ $0.count == 3 }),
              groups.keys.allSatisfy(\.canBeInDouDizhuChain)
        else { return nil }
        let ranks = groups.keys.sorted()
        guard ranks.areConsecutive else { return nil }
        return DouDizhuCombination(
            kind: .airplane,
            cards: cards,
            primaryRank: ranks.max() ?? .three,
            sequenceLength: ranks.count
        )
    }

    static func classifyAirplaneWithSingles(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count >= 8, cards.count.isMultiple(of: 4) else { return nil }
        let wingCount = cards.count / 4
        guard let trioRanks = consecutiveTrioRanks(in: cards, length: wingCount) else { return nil }
        let remaining = cards.removingFirst(count: 3, forEach: trioRanks)
        guard remaining.count == wingCount else { return nil }
        return DouDizhuCombination(
            kind: .airplaneWithSingles,
            cards: cards,
            primaryRank: trioRanks.max() ?? .three,
            sequenceLength: trioRanks.count
        )
    }

    static func classifyAirplaneWithPairs(_ cards: [Card]) -> DouDizhuCombination? {
        guard cards.count >= 10, cards.count.isMultiple(of: 5) else { return nil }
        let pairCount = cards.count / 5
        guard let trioRanks = consecutiveTrioRanks(in: cards, length: pairCount) else { return nil }
        let remaining = cards.removingFirst(count: 3, forEach: trioRanks)
        let groups = rankGroups(remaining)
        guard remaining.count == pairCount * 2,
              groups.count == pairCount,
              groups.values.allSatisfy({ $0.count == 2 })
        else { return nil }
        return DouDizhuCombination(
            kind: .airplaneWithPairs,
            cards: cards,
            primaryRank: trioRanks.max() ?? .three,
            sequenceLength: trioRanks.count
        )
    }

    static func classifyFourWithTwo(_ cards: [Card]) -> DouDizhuCombination? {
        let groups = rankGroups(cards)
        guard let quad = groups.first(where: { $0.value.count == 4 }) else { return nil }
        let remaining = cards.filter { $0.rank != quad.key }
        if cards.count == 6, remaining.count == 2 {
            return DouDizhuCombination(kind: .fourWithTwoSingles, cards: cards, primaryRank: quad.key)
        }
        if cards.count == 8 {
            let remainingGroups = rankGroups(remaining)
            if remainingGroups.count == 2, remainingGroups.values.allSatisfy({ $0.count == 2 }) {
                return DouDizhuCombination(kind: .fourWithTwoPairs, cards: cards, primaryRank: quad.key)
            }
        }
        return nil
    }

    static func allCombinations(in hand: [Card]) -> [DouDizhuCombination] {
        let hand = hand.sortedForHand()
        let groups = rankGroups(hand)
        var combinations: [DouDizhuCombination] = []

        for (_, cards) in groups {
            if let single = classify(Array(cards.prefix(1))) {
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

        if let small = groups[.smallJoker]?.first,
           let big = groups[.bigJoker]?.first {
            combinations.append(DouDizhuCombination(kind: .rocket, cards: [small, big], primaryRank: .bigJoker))
        }

        combinations.append(contentsOf: trioAttachmentCombinations(groups: groups))
        combinations.append(contentsOf: straightCombinations(groups: groups, repeatCount: 1, minimumLength: 5))
        combinations.append(contentsOf: straightCombinations(groups: groups, repeatCount: 2, minimumLength: 3))
        combinations.append(contentsOf: airplaneCombinations(groups: groups))
        combinations.append(contentsOf: fourWithTwoCombinations(groups: groups))

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

    static func trioAttachmentCombinations(groups: [Rank: [Card]]) -> [DouDizhuCombination] {
        var combinations: [DouDizhuCombination] = []
        let trioRanks = groups.keys.filter { (groups[$0]?.count ?? 0) >= 3 && $0 != .smallJoker && $0 != .bigJoker }
        for trioRank in trioRanks {
            let trio = Array((groups[trioRank] ?? []).prefix(3))
            for rank in groups.keys where rank != trioRank {
                if let single = groups[rank]?.first,
                   let combination = classify(trio + [single]) {
                    combinations.append(combination)
                }
                if let cards = groups[rank], cards.count >= 2,
                   let combination = classify(trio + Array(cards.prefix(2))) {
                    combinations.append(combination)
                }
            }
        }
        return combinations
    }

    static func straightCombinations(
        groups: [Rank: [Card]],
        repeatCount: Int,
        minimumLength: Int
    ) -> [DouDizhuCombination] {
        var combinations: [DouDizhuCombination] = []
        let ranks = Rank.douDizhuChainRanks
        for start in ranks.indices {
            var end = start
            while end < ranks.count, (groups[ranks[end]]?.count ?? 0) >= repeatCount {
                let length = end - start + 1
                if length >= minimumLength {
                    let chainRanks = ranks[start...end]
                    let cards = chainRanks.flatMap { rank in
                        Array((groups[rank] ?? []).prefix(repeatCount))
                    }
                    if let combination = classify(cards) {
                        combinations.append(combination)
                    }
                }
                end += 1
            }
        }
        return combinations
    }

    static func airplaneCombinations(groups: [Rank: [Card]]) -> [DouDizhuCombination] {
        var combinations: [DouDizhuCombination] = []
        let ranks = Rank.douDizhuChainRanks
        for start in ranks.indices {
            var end = start
            while end < ranks.count, (groups[ranks[end]]?.count ?? 0) >= 3 {
                let length = end - start + 1
                if length >= 2 {
                    let trioRanks = Array(ranks[start...end])
                    let trioCards = trioRanks.flatMap { rank in
                        Array((groups[rank] ?? []).prefix(3))
                    }
                    if let bare = classify(trioCards) {
                        combinations.append(bare)
                    }

                    let remaining = groups
                        .flatMap(\.value)
                        .removingFirst(count: 3, forEach: trioRanks)
                        .sortedForHand()
                    let singles = lowValueSingles(from: remaining, count: length)
                    if singles.count == length, let combo = classify(trioCards + singles) {
                        combinations.append(combo)
                    }

                    let pairs = lowValuePairs(from: remaining, count: length)
                    if pairs.count == length * 2, let combo = classify(trioCards + pairs) {
                        combinations.append(combo)
                    }
                }
                end += 1
            }
        }
        return combinations
    }

    static func fourWithTwoCombinations(groups: [Rank: [Card]]) -> [DouDizhuCombination] {
        var combinations: [DouDizhuCombination] = []
        for rank in groups.keys where (groups[rank]?.count ?? 0) >= 4 {
            let quad = Array((groups[rank] ?? []).prefix(4))
            let remaining = groups
                .flatMap(\.value)
                .filter { $0.rank != rank }
                .sortedForHand()
            let singles = lowValueSingles(from: remaining, count: 2)
            if singles.count == 2, let combo = classify(quad + singles) {
                combinations.append(combo)
            }
            let pairs = lowValuePairs(from: remaining, count: 2)
            if pairs.count == 4, let combo = classify(quad + pairs) {
                combinations.append(combo)
            }
        }
        return combinations
    }

    static func lowValueSingles(from cards: [Card], count: Int) -> [Card] {
        Array(cards.sortedForHand().prefix(count))
    }

    static func lowValuePairs(from cards: [Card], count: Int) -> [Card] {
        let groups = rankGroups(cards)
        var result: [Card] = []
        for rank in groups.keys.sorted() where (groups[rank]?.count ?? 0) >= 2 {
            result.append(contentsOf: Array((groups[rank] ?? []).prefix(2)))
            if result.count == count * 2 {
                break
            }
        }
        return result
    }

    static func consecutiveTrioRanks(in cards: [Card], length: Int) -> [Rank]? {
        let groups = rankGroups(cards)
        let candidates = Rank.douDizhuChainRanks.filter { (groups[$0]?.count ?? 0) >= 3 }
        guard candidates.count >= length else { return nil }
        for window in candidates.windows(ofCount: length) where window.areConsecutive {
            return window
        }
        return nil
    }

    static func rankGroups(_ cards: [Card]) -> [Rank: [Card]] {
        Dictionary(grouping: cards.sortedForHand(), by: \.rank)
            .mapValues { $0.sortedForHand() }
    }
}

private extension Rank {
    var canBeInDouDizhuChain: Bool {
        rawValue <= Rank.ace.rawValue
    }

    static var douDizhuChainRanks: [Rank] {
        [.three, .four, .five, .six, .seven, .eight, .nine, .ten, .jack, .queen, .king, .ace]
    }
}

private extension Array where Element == Rank {
    var areConsecutive: Bool {
        guard count > 1 else { return true }
        let sortedRanks = sorted()
        for index in 1..<sortedRanks.count {
            guard sortedRanks[index].rawValue == sortedRanks[index - 1].rawValue + 1 else { return false }
        }
        return true
    }

    func windows(ofCount count: Int) -> [[Rank]] {
        guard count > 0, self.count >= count else { return [] }
        return (0...(self.count - count)).map { start in
            Array(self[start..<(start + count)])
        }
    }
}

private extension Array where Element == Card {
    func removingFirst(count: Int, forEach ranks: [Rank]) -> [Card] {
        var remaining = self
        for rank in ranks {
            for _ in 0..<count {
                guard let index = remaining.firstIndex(where: { $0.rank == rank }) else { break }
                remaining.remove(at: index)
            }
        }
        return remaining
    }
}

private extension Array where Element == DouDizhuCombination {
    func sortedForDouDizhuDecision() -> [DouDizhuCombination] {
        sorted {
            let lhsScore = DouDizhuRulesEngine.combinationSortScore($0)
            let rhsScore = DouDizhuRulesEngine.combinationSortScore($1)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return $0.cards.count < $1.cards.count
        }
    }
}
