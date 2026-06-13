import Foundation

public final class DouDizhuGameEngine {
    public private(set) var state: DouDizhuState

    public convenience init() {
        var deck = DeckConfig(deckCount: 1).makeDeck()
        deck.shuffle()
        self.init(deck: deck, startingPlayer: 0)
    }

    public init(deck: [Card], startingPlayer: Int = 0) {
        let players = [
            DouDizhuPlayer(name: "你", isHuman: true),
            DouDizhuPlayer(name: "AI 左", isHuman: false),
            DouDizhuPlayer(name: "AI 右", isHuman: false)
        ]
        let deal = Self.deal(deck: deck)
        self.state = DouDizhuState(
            players: players,
            hands: deal.hands,
            bottomCards: deal.bottomCards,
            currentPlayerIndex: startingPlayer
        )
        appendSystemEvent("开始叫地主")
    }

    public init(state: DouDizhuState) {
        self.state = state
    }

    public static func deal(deck: [Card]) -> (hands: [[Card]], bottomCards: [Card]) {
        let sortedDeck = Array(deck.prefix(54))
        let bottom = Array(sortedDeck.suffix(3)).sortedForHand()
        let playable = Array(sortedDeck.dropLast(3))
        var hands = Array(repeating: [Card](), count: 3)
        for (index, card) in playable.enumerated() {
            hands[index % 3].append(card)
        }
        return (hands.map { $0.sortedForHand() }, bottom)
    }

    public func legalBidActions(for playerIndex: Int) -> [DouDizhuBidAction] {
        guard state.phase == .bidding, state.currentPlayerIndex == playerIndex else { return [] }
        var actions: [DouDizhuBidAction] = [.pass]
        if state.highestBid < 3 {
            for value in (state.highestBid + 1)...3 {
                actions.append(.bid(value))
            }
        }
        return actions
    }

    public func legalPlayActions(for playerIndex: Int) -> [DouDizhuAction] {
        guard state.phase == .playing, state.currentPlayerIndex == playerIndex else { return [] }
        let previous = activePreviousCombination(for: playerIndex)
        let plays = DouDizhuRulesEngine.legalCombinations(in: state.hands[playerIndex], beating: previous)
            .map { DouDizhuAction.play($0.cards) }
        if previous == nil {
            return plays
        }
        return plays + [.pass]
    }

    public func applyBid(_ action: DouDizhuBidAction) throws {
        guard state.phase == .bidding else { throw DouDizhuError.wrongPhase }
        let playerIndex = state.currentPlayerIndex
        guard state.players.indices.contains(playerIndex) else { throw DouDizhuError.notPlayersTurn }

        switch action {
        case .pass:
            appendEvent(
                playerIndex: playerIndex,
                kind: .bid,
                message: "\(state.players[playerIndex].name)不叫"
            )
        case .bid(let value):
            guard value > state.highestBid, value <= 3 else { throw DouDizhuError.illegalBid }
            state.highestBid = value
            state.highestBidderIndex = playerIndex
            appendEvent(
                playerIndex: playerIndex,
                kind: .bid,
                message: "\(state.players[playerIndex].name)叫\(value)分"
            )
        }

        state.bidTurnCount += 1

        if case .bid(3) = action {
            becomeLandlord(playerIndex)
            return
        }

        if state.bidTurnCount >= state.players.count {
            if let bidder = state.highestBidderIndex {
                becomeLandlord(bidder)
            } else {
                state.phase = .noLandlord
                appendSystemEvent("无人叫地主，请重发")
            }
            return
        }

        state.currentPlayerIndex = nextPlayer(after: playerIndex)
    }

    public func applyPlay(_ action: DouDizhuAction) throws {
        guard state.phase == .playing else { throw DouDizhuError.wrongPhase }
        guard !state.isGameOver else { throw DouDizhuError.gameOver }
        let playerIndex = state.currentPlayerIndex
        guard state.players.indices.contains(playerIndex) else { throw DouDizhuError.notPlayersTurn }

        switch action {
        case .pass:
            try pass(playerIndex)
        case .play(let cards):
            try play(cards, by: playerIndex)
        }
    }
}

private extension DouDizhuGameEngine {
    func activePreviousCombination(for playerIndex: Int) -> DouDizhuCombination? {
        guard let lastPlay = state.lastPlay,
              lastPlay.playerIndex != playerIndex
        else { return nil }
        return lastPlay.combination
    }

    func becomeLandlord(_ playerIndex: Int) {
        state.landlordIndex = playerIndex
        state.phase = .playing
        state.currentPlayerIndex = playerIndex
        state.highestBid = max(1, state.highestBid)
        state.hands[playerIndex].append(contentsOf: state.bottomCards)
        state.hands[playerIndex] = state.hands[playerIndex].sortedForHand()
        clearTableRecords()
        appendEvent(
            playerIndex: playerIndex,
            kind: .landlord,
            message: "\(state.players[playerIndex].name)成为地主，底牌加入手牌"
        )
    }

    func play(_ cards: [Card], by playerIndex: Int) throws {
        guard Set(cards).isSubset(of: Set(state.hands[playerIndex])) else {
            throw DouDizhuError.cardsNotInHand
        }
        guard let combination = DouDizhuRulesEngine.classify(cards) else {
            throw DouDizhuError.invalidCombination
        }
        if let previous = activePreviousCombination(for: playerIndex),
           !DouDizhuRulesEngine.canBeat(combination, previous) {
            throw DouDizhuError.cannotBeatPrevious
        }

        state.hands[playerIndex] = state.hands[playerIndex].removing(cards).sortedForHand()
        state.playActionCounts[playerIndex] += 1
        state.passCount = 0

        if combination.isBombLike {
            state.multiplier *= 2
        }

        let record = DouDizhuPlayRecord(
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
            throw DouDizhuError.cannotPassOnLead
        }

        let record = DouDizhuPlayRecord(
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
        guard let landlord = state.landlordIndex else { return }
        let winnerTeam: DouDizhuTeam = winningPlayer == landlord ? .landlord : .farmers
        state.winnerTeam = winnerTeam
        state.phase = .gameOver
        state.scores = scoreLines(winnerTeam: winnerTeam)
        appendSystemEvent(winnerTeam == .landlord ? "地主胜利" : "农民胜利")
    }

    func scoreLines(winnerTeam: DouDizhuTeam) -> [DouDizhuScoreLine] {
        guard let landlord = state.landlordIndex else { return [] }
        var multiplier = max(1, state.highestBid) * max(1, state.multiplier)
        var notes = ["底分\(max(1, state.highestBid))", "倍数x\(state.multiplier)"]

        if winnerTeam == .landlord {
            let farmersNeverPlayed = state.players.indices
                .filter { $0 != landlord }
                .allSatisfy { state.playActionCounts[$0] == 0 }
            if farmersNeverPlayed {
                multiplier *= 2
                notes.append("春天x2")
            }
        } else if state.playActionCounts[landlord] <= 1 {
            multiplier *= 2
            notes.append("反春天x2")
        }

        return state.players.indices.map { index in
            let team: DouDizhuTeam = index == landlord ? .landlord : .farmers
            let isWinner = team == winnerTeam
            let landlordMagnitude = multiplier * 2
            let farmerMagnitude = multiplier
            let magnitude = team == .landlord ? landlordMagnitude : farmerMagnitude
            return DouDizhuScoreLine(
                playerIndex: index,
                playerName: state.players[index].name,
                team: team,
                delta: isWinner ? magnitude : -magnitude,
                notes: notes
            )
        }
    }

    func nextPlayer(after playerIndex: Int) -> Int {
        (playerIndex + 1) % state.players.count
    }

    func appendEvent(playerIndex: Int, kind: DouDizhuEventKind, message: String) {
        let record = DouDizhuPlayRecord(
            playerIndex: playerIndex,
            playerName: state.players[playerIndex].name,
            combination: nil,
            kind: kind,
            message: message
        )
        state.visibleRecord = record
        state.eventLog.append(record)
    }

    func appendSystemEvent(_ message: String) {
        let record = DouDizhuPlayRecord(
            playerIndex: -1,
            playerName: "系统",
            combination: nil,
            kind: .system,
            message: message
        )
        state.visibleRecord = record
        state.eventLog.append(record)
    }

    func setTableRecord(_ record: DouDizhuPlayRecord) {
        guard state.tableRecords.indices.contains(record.playerIndex) else { return }
        state.tableRecords[record.playerIndex] = record
    }

    func clearTableRecords(keeping playerIndex: Int? = nil) {
        let kept = playerIndex.flatMap { index in
            state.tableRecords.indices.contains(index) ? state.tableRecords[index] : nil
        }
        state.tableRecords = Array(repeating: nil, count: state.players.count)
        if let playerIndex, state.tableRecords.indices.contains(playerIndex) {
            state.tableRecords[playerIndex] = kept
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
}
