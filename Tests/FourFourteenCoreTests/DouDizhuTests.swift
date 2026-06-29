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
                [ddzCard(.three), ddzCard(.five)],
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

        try engine.applyPlay(.play([ddzCard(.three)]))
        #expect(engine.state.lastPlay?.combination?.primaryRank == .three)
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

    @Test("farmer usually does not beat teammate when landlord is not short")
    func farmerDoesNotBeatTeammateWithoutUrgency() throws {
        let previous = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.three, .hearts), ddzCard(.three, .clubs)
        ]))
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [
                    ddzCard(.seven), ddzCard(.eight), ddzCard(.nine),
                    ddzCard(.ten), ddzCard(.jack), ddzCard(.queen),
                    ddzCard(.king), ddzCard(.ace)
                ],
                [ddzCard(.five), ddzCard(.six), ddzCard(.seven, .clubs)],
                [
                    ddzCard(.four, .hearts), ddzCard(.four, .clubs),
                    ddzCard(.six, .spades), ddzCard(.seven, .spades),
                    ddzCard(.eight, .spades), ddzCard(.nine, .spades)
                ]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 2,
            landlordIndex: 0,
            highestBid: 1,
            lastPlay: DouDizhuPlayRecord(
                playerIndex: 1,
                playerName: Self.players[1].name,
                combination: previous,
                kind: .play,
                message: "AI1出对子"
            )
        )

        #expect(DouDizhuAIPlayer().chooseAction(state: state, for: 2) == .pass)
    }

    @Test("farmer can beat teammate to finish")
    func farmerCanBeatTeammateToFinish() throws {
        let previous = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.three, .hearts), ddzCard(.three, .clubs)
        ]))
        let finishingPair = [ddzCard(.four, .hearts), ddzCard(.four, .clubs)]
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.seven), ddzCard(.eight), ddzCard(.nine), ddzCard(.ten), ddzCard(.jack)],
                [ddzCard(.five), ddzCard(.six), ddzCard(.seven, .clubs)],
                finishingPair
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 2,
            landlordIndex: 0,
            highestBid: 1,
            lastPlay: DouDizhuPlayRecord(
                playerIndex: 1,
                playerName: Self.players[1].name,
                combination: previous,
                kind: .play,
                message: "AI1出对子"
            )
        )

        #expect(DouDizhuAIPlayer().chooseAction(state: state, for: 2) == .play(finishingPair.sortedForHand()))
    }

    @Test("farmer can overtake teammate when short landlord is next to act")
    func farmerCanOvertakeTeammateWhenShortLandlordIsNext() throws {
        let previous = try #require(DouDizhuRulesEngine.classify([ddzCard(.ace, .hearts)]))
        let two = ddzCard(.two, .spades)
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.five), ddzCard(.king), ddzCard(.two), ddzCard(.smallJoker, nil)],
                [ddzCard(.three), ddzCard(.four), ddzCard(.five, .clubs)],
                [ddzCard(.three), ddzCard(.four), ddzCard(.five), ddzCard(.six), ddzCard(.seven), two]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 2,
            landlordIndex: 0,
            highestBid: 1,
            lastPlay: DouDizhuPlayRecord(
                playerIndex: 1,
                playerName: Self.players[1].name,
                combination: previous,
                kind: .play,
                message: "AI1出单张"
            )
        )

        #expect(DouDizhuAIPlayer().chooseAction(state: state, for: 2) == .play([two]))
    }

    @Test("farmer presses a short landlord with the cheapest ordinary card")
    func farmerPressesShortLandlordWithCheapCard() throws {
        let previous = try #require(DouDizhuRulesEngine.classify([ddzCard(.five)]))
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.king)],
                [ddzCard(.six), ddzCard(.seven), ddzCard(.eight)],
                [ddzCard(.nine), ddzCard(.ten), ddzCard(.jack)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 1,
            landlordIndex: 0,
            highestBid: 1,
            lastPlay: DouDizhuPlayRecord(
                playerIndex: 0,
                playerName: Self.players[0].name,
                combination: previous,
                kind: .play,
                message: "Human出单张"
            )
        )

        #expect(DouDizhuAIPlayer().chooseAction(state: state, for: 1) == .play([ddzCard(.six)]))
    }

    @Test("farmer uses ordinary pressure before bomb against short landlord")
    func farmerUsesOrdinaryCardBeforeBombAgainstShortLandlord() throws {
        let previous = try #require(DouDizhuRulesEngine.classify([ddzCard(.five)]))
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.king)],
                [
                    ddzCard(.six),
                    ddzCard(.seven, .hearts), ddzCard(.seven, .clubs),
                    ddzCard(.seven, .spades), ddzCard(.seven, .diamonds)
                ],
                [ddzCard(.nine), ddzCard(.ten), ddzCard(.jack)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 1,
            landlordIndex: 0,
            highestBid: 1,
            lastPlay: DouDizhuPlayRecord(
                playerIndex: 0,
                playerName: Self.players[0].name,
                combination: previous,
                kind: .play,
                message: "Human出单张"
            )
        )

        let action = DouDizhuAIPlayer().chooseAction(state: state, for: 1)
        let combination = try #require(DouDizhuRulesEngine.classify(action.cards))
        #expect(combination.kind == .single)
        #expect(action.cards.map(\.rank) == [.six])
    }

    @Test("farmer uses bomb when no ordinary answer can stop a short landlord")
    func farmerUsesBombWhenNoOrdinaryAnswerCanStopShortLandlord() throws {
        let previous = try #require(DouDizhuRulesEngine.classify([
            ddzCard(.ace, .hearts), ddzCard(.ace, .clubs)
        ]))
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.king)],
                [
                    ddzCard(.three),
                    ddzCard(.seven, .hearts), ddzCard(.seven, .clubs),
                    ddzCard(.seven, .spades), ddzCard(.seven, .diamonds)
                ],
                [ddzCard(.nine), ddzCard(.ten), ddzCard(.jack)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 1,
            landlordIndex: 0,
            highestBid: 1,
            lastPlay: DouDizhuPlayRecord(
                playerIndex: 0,
                playerName: Self.players[0].name,
                combination: previous,
                kind: .play,
                message: "Human出对子"
            )
        )

        let action = DouDizhuAIPlayer().chooseAction(state: state, for: 1)
        let combination = try #require(DouDizhuRulesEngine.classify(action.cards))
        #expect(combination.kind == .bomb)
    }

    @Test("AI avoids naked airplane in middle game when wings are available")
    func aiAvoidsNakedAirplaneInMiddleGameWhenWingsAreAvailable() throws {
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.king), ddzCard(.ace), ddzCard(.two)],
                [
                    ddzCard(.three, .hearts), ddzCard(.three, .clubs), ddzCard(.three, .spades),
                    ddzCard(.four, .hearts), ddzCard(.four, .clubs), ddzCard(.four, .spades),
                    ddzCard(.five), ddzCard(.six), ddzCard(.nine), ddzCard(.ten)
                ],
                [ddzCard(.seven), ddzCard(.eight), ddzCard(.jack)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 1,
            landlordIndex: 0,
            highestBid: 1
        )

        let action = DouDizhuAIPlayer().chooseAction(state: state, for: 1)
        let combination = try #require(DouDizhuRulesEngine.classify(action.cards))
        #expect(combination.kind != .airplane)
    }

    @Test("AI allows naked airplane when it immediately finishes")
    func aiAllowsNakedAirplaneToFinish() throws {
        let hand = [
            ddzCard(.three, .hearts), ddzCard(.three, .clubs), ddzCard(.three, .spades),
            ddzCard(.four, .hearts), ddzCard(.four, .clubs), ddzCard(.four, .spades)
        ]
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.king), ddzCard(.ace), ddzCard(.two)],
                hand,
                [ddzCard(.seven), ddzCard(.eight), ddzCard(.jack)]
            ],
            bottomCards: [],
            phase: .playing,
            currentPlayerIndex: 1,
            landlordIndex: 0,
            highestBid: 1
        )

        let action = DouDizhuAIPlayer().chooseAction(state: state, for: 1)
        let combination = try #require(DouDizhuRulesEngine.classify(action.cards))
        #expect(action.cards == hand.sortedForHand())
        #expect(combination.kind == .airplane)
    }

    @Test("AI bid choice remains legal")
    func aiBidChoiceRemainsLegal() {
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [
                    ddzCard(.smallJoker, nil), ddzCard(.bigJoker, nil),
                    ddzCard(.two, .hearts), ddzCard(.two, .clubs),
                    ddzCard(.ace), ddzCard(.king)
                ],
                [ddzCard(.three), ddzCard(.four), ddzCard(.five)],
                [ddzCard(.six), ddzCard(.seven), ddzCard(.eight)]
            ],
            bottomCards: [],
            phase: .bidding,
            currentPlayerIndex: 0,
            highestBid: 1
        )

        let ai = DouDizhuAIPlayer()
        #expect(ai.legalBidActions(from: state, for: 0).contains(ai.chooseBid(state: state, for: 0)))
    }

    @Test("AI final bidder takes one point when everyone passed")
    func aiFinalBidderTakesOnePointWhenEveryonePassed() {
        let state = DouDizhuState(
            players: Self.players,
            hands: [
                [ddzCard(.three), ddzCard(.four), ddzCard(.five)],
                [ddzCard(.six), ddzCard(.seven), ddzCard(.eight)],
                [ddzCard(.nine), ddzCard(.ten), ddzCard(.jack)]
            ],
            bottomCards: [],
            phase: .bidding,
            currentPlayerIndex: 2,
            highestBid: 0,
            bidTurnCount: 2
        )

        #expect(DouDizhuAIPlayer().chooseBid(state: state, for: 2) == .bid(1))
    }

    private static let players = [
        DouDizhuPlayer(name: "Human", isHuman: true),
        DouDizhuPlayer(name: "AI1", isHuman: false),
        DouDizhuPlayer(name: "AI2", isHuman: false)
    ]
}
