import Testing
@testable import FourFourteenCore

private func c(_ rank: Rank, _ suit: Suit? = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("RulesEngine")
struct RulesEngineTests {
    @Test("recognizes 4A4 as the top rocket")
    func recognizesRocket414() throws {
        let combo = try #require(RulesEngine.classify([
            c(.four, .hearts),
            c(.four, .spades),
            c(.ace, .clubs)
        ]))

        #expect(combo.kind == .rocket414)

        let doubleJoker = try #require(RulesEngine.classify([
            c(.smallJoker, nil),
            c(.bigJoker, nil)
        ]))
        #expect(RulesEngine.canBeat(combo, doubleJoker))
        #expect(!RulesEngine.canBeat(doubleJoker, combo))
    }

    @Test("recognizes single and pair dragons but excludes 2 and jokers")
    func recognizesRuns() throws {
        let singleRun = try #require(RulesEngine.classify([
            c(.five, .hearts),
            c(.six, .clubs),
            c(.seven, .spades)
        ]))
        #expect(singleRun.kind == .singleRun)

        let pairRun = try #require(RulesEngine.classify([
            c(.five, .hearts), c(.five, .clubs),
            c(.six, .hearts), c(.six, .clubs),
            c(.seven, .hearts), c(.seven, .clubs)
        ]))
        #expect(pairRun.kind == .pairRun)
        #expect(!RulesEngine.canBeat(pairRun, singleRun))

        #expect(RulesEngine.classify([
            c(.queen, .hearts),
            c(.king, .hearts),
            c(.ace, .hearts),
            c(.two, .hearts)
        ]) == nil)
    }

    @Test("dragons only compare against the same dragon type and length")
    func comparesDragonsByTypeAndLength() throws {
        let singleRun345 = try #require(RulesEngine.classify([
            c(.three, .hearts),
            c(.four, .clubs),
            c(.five, .spades)
        ]))
        let singleRun456 = try #require(RulesEngine.classify([
            c(.four, .hearts),
            c(.five, .clubs),
            c(.six, .spades)
        ]))
        let singleRun4567 = try #require(RulesEngine.classify([
            c(.four, .hearts),
            c(.five, .clubs),
            c(.six, .spades),
            c(.seven, .diamonds)
        ]))
        let pairRun334455 = try #require(RulesEngine.classify([
            c(.three, .hearts), c(.three, .clubs),
            c(.four, .hearts), c(.four, .clubs),
            c(.five, .hearts), c(.five, .clubs)
        ]))
        let pairRun445566 = try #require(RulesEngine.classify([
            c(.four, .hearts), c(.four, .clubs),
            c(.five, .hearts), c(.five, .clubs),
            c(.six, .hearts), c(.six, .clubs)
        ]))

        #expect(RulesEngine.canBeat(singleRun456, singleRun345))
        #expect(!RulesEngine.canBeat(singleRun4567, singleRun345))
        #expect(!RulesEngine.canBeat(pairRun334455, singleRun345))
        #expect(RulesEngine.canBeat(pairRun445566, pairRun334455))
    }

    @Test("three-card bombs beat single dragons but not pair dragons or triad attachments")
    func comparesSmallAndLargeBombsAgainstOrdinaryCombinations() throws {
        let singleRun345 = try #require(RulesEngine.classify([
            c(.three, .diamonds),
            c(.four, .diamonds),
            c(.five, .diamonds)
        ]))
        let pairRun334455 = try #require(RulesEngine.classify([
            c(.three, .hearts), c(.three, .clubs),
            c(.four, .hearts), c(.four, .clubs),
            c(.five, .hearts), c(.five, .clubs)
        ]))
        let triadWithSingle = try #require(RulesEngine.classify([
            c(.six, .hearts),
            c(.six, .clubs),
            c(.six, .spades),
            c(.nine, .hearts)
        ]))
        let threeThrees = try #require(RulesEngine.classify([
            c(.three, .hearts),
            c(.three, .clubs),
            c(.three, .spades)
        ]))
        let fourSevens = try #require(RulesEngine.classify([
            c(.seven, .hearts),
            c(.seven, .clubs),
            c(.seven, .spades),
            c(.seven, .diamonds)
        ]))
        let pair = try #require(RulesEngine.classify([
            c(.ace, .hearts),
            c(.ace, .clubs)
        ]))

        #expect(RulesEngine.canBeat(threeThrees, pair))
        #expect(RulesEngine.canBeat(threeThrees, singleRun345))
        #expect(!RulesEngine.canBeat(threeThrees, pairRun334455))
        #expect(!RulesEngine.canBeat(threeThrees, triadWithSingle))
        #expect(RulesEngine.canBeat(fourSevens, pairRun334455))
        #expect(RulesEngine.canBeat(fourSevens, triadWithSingle))
    }

    @Test("compares mechanical multi-deck bombs by count then rank")
    func comparesMultiDeckBombs() throws {
        let fourFives = try #require(RulesEngine.classify([
            c(.five, .diamonds),
            c(.five, .clubs),
            c(.five, .hearts),
            c(.five, .spades)
        ]))
        let fiveThrees = try #require(RulesEngine.classify([
            c(.three, .diamonds, deck: 0),
            c(.three, .clubs, deck: 0),
            c(.three, .hearts, deck: 0),
            c(.three, .spades, deck: 0),
            c(.three, .diamonds, deck: 1)
        ]))
        let fourSixes = try #require(RulesEngine.classify([
            c(.six, .diamonds),
            c(.six, .clubs),
            c(.six, .hearts),
            c(.six, .spades)
        ]))

        #expect(RulesEngine.canBeat(fiveThrees, fourFives))
        #expect(RulesEngine.canBeat(fourSixes, fourFives))
        #expect(!RulesEngine.canBeat(fourFives, fourSixes))
    }

    @Test("finds available 4A4 rocket cards without changing hand order")
    func findsRocket414Cards() throws {
        let hand = [
            c(.four, .hearts, deck: 0),
            c(.four, .clubs, deck: 0),
            c(.ace, .spades, deck: 0),
            c(.ace, .diamonds, deck: 1),
            c(.four, .diamonds, deck: 1),
            c(.four, .spades, deck: 1)
        ]

        let rocket = try #require(hand.rocket414Cards())
        #expect(rocket.count == 3)
        #expect(rocket.count(of: .four) == 2)
        #expect(rocket.count(of: .ace) == 1)
        #expect(hand.rocket414Count() == 2)
    }

    @Test("legal action enumeration includes reactions and hints use legal cards")
    func hintUsesLegalAction() throws {
        let players = [
            GamePlayer(name: "Human", isHuman: true),
            GamePlayer(name: "AI1", isHuman: false),
            GamePlayer(name: "AI2", isHuman: false),
            GamePlayer(name: "AI3", isHuman: false)
        ]
        let engine = GameEngine(
            players: players,
            hands: [
                [c(.five), c(.six)],
                [c(.seven)],
                [c(.eight)],
                [c(.nine)]
            ],
            startingPlayer: 0
        )

        let hint = try #require(HintEngine.bestAction(state: engine.state, for: 0))
        #expect(!hint.cards.isEmpty)
        #expect(Set(hint.cards).isSubset(of: Set(engine.state.hands[0])))
    }
}
