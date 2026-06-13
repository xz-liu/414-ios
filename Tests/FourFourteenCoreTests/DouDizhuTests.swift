import Testing
@testable import FourFourteenCore

private func ddzCard(_ rank: Rank, _ suit: Suit? = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("DouDizhu")
struct DouDizhuTests {
    @Test("deals one deck into 17 cards each plus 3 bottom cards")
    func dealsCardsAndBottom() {
        let deck = DeckConfig(deckCount: 1).makeDeck()
        let deal = DouDizhuGameEngine.deal(deck: deck)

        #expect(deal.hands.map(\.count) == [17, 17, 17])
        #expect(deal.bottomCards.count == 3)
        #expect(Set((deal.hands.flatMap { $0 } + deal.bottomCards).map(\.id)).count == 54)
    }

    @Test("recognizes standard combinations")
    func recognizesCombinations() throws {
        let straight = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.three), ddzCard(.four), ddzCard(.five), ddzCard(.six), ddzCard(.seven)
        ]))
        #expect(straight.kind == .singleStraight)

        let pairStraight = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.three, .hearts), ddzCard(.three, .clubs),
            ddzCard(.four, .hearts), ddzCard(.four, .clubs),
            ddzCard(.five, .hearts), ddzCard(.five, .clubs)
        ]))
        #expect(pairStraight.kind == .pairStraight)

        let airplane = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.three, .hearts), ddzCard(.three, .clubs), ddzCard(.three, .spades),
            ddzCard(.four, .hearts), ddzCard(.four, .clubs), ddzCard(.four, .spades),
            ddzCard(.six), ddzCard(.seven)
        ]))
        #expect(airplane.kind == .airplaneWithSingles)

        let rocket = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.smallJoker, nil), ddzCard(.bigJoker, nil)
        ]))
        #expect(rocket.kind == .rocket)
    }

    @Test("bombs beat ordinary combinations and rocket beats bombs")
    func comparesBombsAndRocket() throws {
        let pair = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.ace, .hearts), ddzCard(.ace, .clubs)
        ]))
        let bomb = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.three, .hearts), ddzCard(.three, .clubs), ddzCard(.three, .spades), ddzCard(.three, .diamonds)
        ]))
        let higherBomb = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.four, .hearts), ddzCard(.four, .clubs), ddzCard(.four, .spades), ddzCard(.four, .diamonds)
        ]))
        let rocket = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.smallJoker, nil), ddzCard(.bigJoker, nil)
        ]))

        #expect(DouDizhuRulesEngine.canBeat(bomb, pair))
        #expect(DouDizhuRulesEngine.canBeat(higherBomb, bomb))
        #expect(DouDizhuRulesEngine.canBeat(rocket, higherBomb))
        #expect(!DouDizhuRulesEngine.canBeat(higherBomb, rocket))
    }

    @Test("bidding assigns landlord and gives bottom cards")
    func biddingAssignsLandlord() throws {
        let engine = DouDizhuGameEngine(deck: DeckConfig(deckCount: 1).makeDeck(), startingPlayer: 0)

        try engine.applyBid(.bid(2))
        try engine.applyBid(.pass)
        try engine.applyBid(.pass)

        #expect(engine.state.phase == .playing)
        #expect(engine.state.landlordIndex == 0)
        #expect(engine.state.hands[0].count == 20)
        #expect(engine.state.currentPlayerIndex == 0)
    }

    @Test("two passes return lead to the last player who played")
    func passesReturnLead() throws {
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.five), ddzCard(.six)],
                [ddzCard(.seven)],
                [ddzCard(.eight)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 0,
            landlordIndex: 0,
            highestBid: 1
        )
        let engine = DouDizhuGameEngine(state: state)

        try engine.applyPlay(.play([ddzCard(.five)]))
        try engine.applyPlay(.pass)
        try engine.applyPlay(.pass)

        #expect(engine.state.currentPlayerIndex == 0)
        #expect(engine.state.lastPlay == nil)
        #expect(engine.state.passCount == 0)
    }

    @Test("first empty hand ends game and scores landlord win")
    func firstEmptyHandEndsGame() throws {
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.five)],
                [ddzCard(.seven)],
                [ddzCard(.eight)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 0,
            landlordIndex: 0,
            highestBid: 1
        )
        let engine = DouDizhuGameEngine(state: state)

        try engine.applyPlay(.play([ddzCard(.five)]))

        #expect(engine.state.phase == .gameOver)
        #expect(engine.state.winnerTeam == .landlord)
        let landlordScore = try #require(engine.state.scores.first { $0.playerIndex == 0 })
        #expect(landlordScore.delta > 0)
    }

    @Test("AI and hint choose legal play actions")
    func aiAndHintChooseLegalActions() throws {
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.five), ddzCard(.six), ddzCard(.seven), ddzCard(.eight), ddzCard(.nine)],
                [ddzCard(.three), ddzCard(.three, .clubs), ddzCard(.ace)],
                [ddzCard(.four), ddzCard(.four, .clubs), ddzCard(.king)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 0,
            landlordIndex: 0,
            highestBid: 1
        )

        let hint = try #require(DouDizhuHintEngine.bestAction(state: state, for: 0))
        #expect(DouDizhuAIPlayer().legalPlayActions(from: state, for: 0).contains(hint))
        #expect(!hint.cards.isEmpty)
    }

    private static let players = [
        DouDizhuPlayer(name: "Human", isHuman: true),
        DouDizhuPlayer(name: "AI1", isHuman: false),
        DouDizhuPlayer(name: "AI2", isHuman: false)
    ]
}
