import Foundation

struct PublicCardMemory: Sendable {
    let deckCount: Int
    let playerIndex: Int
    let visibleCards: [Card]
    let ownCards: [Card]

    private let visibleRankCounts: [Rank: Int]
    private let ownRankCounts: [Rank: Int]
    private let opponentHandCounts: [Int]

    init(state: GameState, playerIndex: Int) {
        self.deckCount = max(1, state.deckCount)
        self.playerIndex = playerIndex
        self.visibleCards = state.eventLog.flatMap { record in
            record.combination?.cards ?? []
        }
        self.ownCards = state.hands.indices.contains(playerIndex) ? state.hands[playerIndex] : []
        self.visibleRankCounts = Dictionary(grouping: visibleCards, by: \.rank).mapValues(\.count)
        self.ownRankCounts = Dictionary(grouping: ownCards, by: \.rank).mapValues(\.count)
        self.opponentHandCounts = state.hands.indices
            .filter { $0 != playerIndex }
            .map { state.hands[$0].count }
    }

    func opponentAvailableCount(_ rank: Rank) -> Int {
        max(0, totalCount(of: rank) - visibleCount(of: rank) - ownCount(of: rank))
    }

    func rankExhausted(_ rank: Rank) -> Bool {
        opponentAvailableCount(rank) == 0
    }

    var opponentsCanHaveRocket414: Bool {
        opponentAvailableCount(.four) >= 2 &&
            opponentAvailableCount(.ace) >= 1 &&
            opponentCanHold(cards: 3)
    }

    var opponentsCanHaveDoubleJoker: Bool {
        opponentAvailableCount(.smallJoker) >= 1 &&
            opponentAvailableCount(.bigJoker) >= 1 &&
            opponentCanHold(cards: 2)
    }

    func opponentsCanHaveSameRankBomb(rank: Rank, count: Int) -> Bool {
        guard rank != .smallJoker, rank != .bigJoker, count >= 3 else { return false }
        return opponentAvailableCount(rank) >= count && opponentCanHold(cards: count)
    }

    func opponentsCanCha(rank: Rank) -> Bool {
        guard rank != .smallJoker, rank != .bigJoker else { return false }
        return opponentAvailableCount(rank) >= 2 && opponentCanHold(cards: 2)
    }

    func opponentsCanGou(rank: Rank) -> Bool {
        opponentAvailableCount(rank) >= 1 && opponentCanHold(cards: 1)
    }

    func opponentsCanBeatSameRankBomb(_ combination: Combination) -> Bool {
        guard combination.kind == .sameRankBomb else { return false }
        let sameCount = combination.sameRankCount
        let primaryValue = combination.primaryRank?.rawValue ?? -1
        return Rank.allCases.contains { rank in
            rank != .smallJoker &&
                rank != .bigJoker &&
                (
                    opponentsCanHaveSameRankBomb(rank: rank, count: sameCount + 1) ||
                    (rank.rawValue > primaryValue && opponentsCanHaveSameRankBomb(rank: rank, count: sameCount))
                )
        }
    }

    private func visibleCount(of rank: Rank) -> Int {
        visibleRankCounts[rank] ?? 0
    }

    private func ownCount(of rank: Rank) -> Int {
        ownRankCounts[rank] ?? 0
    }

    private func totalCount(of rank: Rank) -> Int {
        rank == .smallJoker || rank == .bigJoker ? deckCount : deckCount * 4
    }

    private func opponentCanHold(cards count: Int) -> Bool {
        opponentHandCounts.contains { $0 >= count }
    }
}
