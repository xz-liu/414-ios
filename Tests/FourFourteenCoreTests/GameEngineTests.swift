import Foundation
import Testing
@testable import FourFourteenCore

private func card(_ rank: Rank, _ suit: Suit? = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("GameEngine")
struct GameEngineTests {
    @Test("deals one deck as 14, 14, 13, 13 and preserves unique identities")
    func dealsOneDeck() {
        let deck = DeckConfig(deckCount: 1).makeDeck()
        let hands = GameEngine.deal(deck: deck, playerCount: 4)

        #expect(hands.map(\.count) == [14, 14, 13, 13])
        #expect(Set(hands.flatMap { $0 }.map(\.id)).count == 54)
        #expect(GameEngine.findHeartThreeHolder(in: hands) != nil)
    }

    @Test("three passes return lead to the last player who played")
    func threePassesResetLead() throws {
        let engine = GameEngine(
            players: Self.players,
            hands: [
                [card(.five), card(.nine)],
                [card(.six)],
                [card(.seven)],
                [card(.eight)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([card(.five)]))
        try engine.apply(.pass)
        try engine.apply(.pass)
        try engine.apply(.pass)

        #expect(engine.state.prompt.kind == .lead)
        #expect(engine.state.prompt.playerIndex == 0)
    }

    @Test("cha and gou transfer lead and cannot be beaten")
    func chaGouTransferLead() throws {
        let engine = GameEngine(
            players: Self.players,
            hands: [
                [card(.five, .hearts), card(.nine)],
                [card(.five, .diamonds), card(.five, .clubs), card(.eight)],
                [card(.five, .spades), card(.six)],
                [card(.seven)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([card(.five, .hearts)]))
        #expect(engine.state.prompt.kind == .cha)
        #expect(engine.state.prompt.playerIndex == 1)

        try engine.apply(.cha([card(.five, .diamonds), card(.five, .clubs)]))
        #expect(engine.state.prompt.kind == .gou)
        #expect(engine.state.prompt.playerIndex == 2)

        try engine.apply(.gou(card(.five, .spades)))
        #expect(engine.state.prompt.kind == .lead)
        #expect(engine.state.prompt.playerIndex == 2)
        #expect(engine.state.lastPlayableRecord == nil)
    }

    @Test("first player to empty hand ends game and scores remaining cards")
    func firstOutEndsGame() throws {
        let engine = GameEngine(
            players: Self.players,
            hands: [
                [card(.five)],
                [card(.smallJoker, nil), card(.bigJoker, nil), card(.six)],
                [card(.seven)],
                [card(.eight)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([card(.five)]))

        #expect(engine.state.isGameOver)
        #expect(engine.state.winnerIndex == 0)
        let ai1 = try #require(engine.state.scores.first { $0.playerIndex == 1 })
        #expect(ai1.multiplier == 4)
        #expect(ai1.penalty == 12)
    }

    @Test("AI only chooses actions from the legal action set")
    func aiChoosesLegalAction() throws {
        let engine = GameEngine(
            players: Self.players,
            hands: [
                [card(.five), card(.nine)],
                [card(.six), card(.ten)],
                [card(.seven)],
                [card(.eight)]
            ],
            startingPlayer: 0
        )
        try engine.apply(.play([card(.five)]))

        let ai = AIPlayer()
        let action = ai.chooseAction(state: engine.state, for: 1)
        #expect(engine.legalActions(for: 1).contains(action))
    }

    @Test("AI avoids gou when it would break an important straight")
    func aiAvoidsGouThatBreaksStraight() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.king, .clubs)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .gou, playerIndex: 1, baseRank: .five)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .pass)
    }

    @Test("AI still takes gou when it does not damage hand structure")
    func aiTakesCheapGou() {
        let five = card(.five, .hearts)
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [five, card(.king, .clubs)],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .gou, playerIndex: 1, baseRank: .five)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .gou(five))
    }

    @Test("AI avoids following with a card that breaks a straight when another single can answer")
    func aiAvoidsBreakingStraightOnFollow() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.king, .clubs)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.four, .clubs)], primaryRank: .four),
                kind: .normal,
                message: "Human出单张"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .play([card(.king, .clubs)]))
    }

    @Test("AI follows with a duplicate rank when that preserves a straight")
    func aiUsesDuplicateSingleToPreserveStraight() {
        let safeSix = card(.six, .clubs)
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    safeSix,
                    card(.six, .hearts),
                    card(.seven, .hearts)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.four, .clubs)], primaryRank: .four),
                kind: .normal,
                message: "Human出单张"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .play([safeSix]))
    }

    @Test("AI leads with a complete straight instead of peeling one card from it")
    func aiLeadsWithStraightWhenItReducesHandBurden() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.king, .clubs)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let playedRanks = action.cards.map(\.rank)
        #expect(playedRanks == [.three, .four, .five, .six, .seven])
    }

    @Test("AI splits overlapping straight material into two playable runs")
    func aiSplitsOverlappingRuns() throws {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .clubs),
                    card(.five, .hearts),
                    card(.six, .clubs),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.eight, .hearts),
                    card(.nine, .hearts)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action.cards.map(\.rank) == [.three, .four, .five, .six])

        let remaining = state.hands[1].removingForTest(action.cards)
        let next = try #require(RulesEngine.classify(remaining))
        #expect(next.kind == .singleRun)
        #expect(next.sequenceLength == 5)
    }

    @Test("reaction pass is silent but normal follow pass remains public")
    func reactionPassIsSilent() throws {
        let engine = GameEngine(
            players: Self.players,
            hands: [
                [card(.five, .hearts), card(.nine)],
                [card(.five, .diamonds), card(.five, .clubs), card(.eight)],
                [card(.seven)],
                [card(.ten)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([card(.five, .hearts)]))
        let visibleBefore = engine.state.visibleRecord
        let eventCountBefore = engine.state.eventLog.count

        try engine.apply(.pass)

        #expect(engine.state.eventLog.count == eventCountBefore)
        #expect(engine.state.visibleRecord == visibleBefore)
        #expect(!engine.state.eventLog.contains { $0.message.contains("放弃") })

        try engine.apply(.pass)

        #expect(engine.state.eventLog.count == eventCountBefore + 1)
        #expect(engine.state.eventLog.last?.message == "AI1过")
    }

    @Test("AI avoids spending two twos on a likely unprofitable cha")
    func aiAvoidsWastefulChaWithTwos() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.eight), card(.nine), card(.ten)],
                [
                    card(.two, .hearts),
                    card(.two, .spades),
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts)
                ],
                [card(.jack)],
                [card(.queen)]
            ],
            prompt: TurnPrompt(kind: .cha, playerIndex: 1, baseRank: .two)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .pass)
    }

    @Test("AI does not open with triad plus pair while the triad is still valuable as a bomb")
    func aiAvoidsEarlyTriadWithPair() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [],
                [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .spades),
                    card(.four, .hearts),
                    card(.four, .clubs),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.eight, .hearts),
                    card(.nine, .hearts),
                    card(.ten, .hearts)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let combination = RulesEngine.classify(action.cards)
        #expect(combination?.kind == .singleRun)
        #expect(action.cards.map(\.rank) == [.six, .seven, .eight, .nine, .ten])
    }

    @Test("AI may use triad plus pair when it immediately finishes")
    func aiUsesTriadWithPairToFinish() {
        let cards = [
            card(.three, .hearts),
            card(.three, .diamonds),
            card(.three, .spades),
            card(.four, .hearts),
            card(.four, .clubs)
        ]
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [[], cards, [], []],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(Set(action.cards) == Set(cards))
        #expect(RulesEngine.classify(action.cards)?.kind == .triadWithPair)
    }

    @Test("AI passes instead of overkilling a low value follow with a two")
    func aiPassesInsteadOfWastingTwo() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [
                    card(.three, .clubs),
                    card(.four, .clubs),
                    card(.five, .clubs),
                    card(.six, .clubs),
                    card(.seven, .clubs),
                    card(.eight),
                    card(.nine),
                    card(.ten)
                ],
                [
                    card(.two, .hearts),
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.king, .clubs)], primaryRank: .king),
                kind: .normal,
                message: "Human出单张"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .pass)
    }

    @Test("AI pressure rises before opponents are down to two cards")
    func aiSpendsTwoWhenTablePressureIsHigh() {
        let two = card(.two, .hearts)
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [
                    card(.three, .clubs),
                    card(.four, .clubs),
                    card(.five, .clubs),
                    card(.six, .clubs),
                    card(.seven, .clubs),
                    card(.bigJoker, nil)
                ],
                [
                    two,
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.king, .clubs)], primaryRank: .king),
                kind: .normal,
                message: "Human出单张"
            ),
            cardsPlayedCount: [16, 12, 8, 6]
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .play([two]))
    }

    @Test("AI spends a two to stop a player who is close to out")
    func aiUsesTwoWhenOpponentIsCloseToOut() {
        let two = card(.two, .hearts)
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.eight)],
                [
                    two,
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts)
                ],
                [],
                []
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.king, .clubs)], primaryRank: .king),
                kind: .normal,
                message: "Human出单张"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action == .play([two]))
    }

    @Test("AI leads a non-single shape when an opponent has one card")
    func aiBlocksOneCardOpponentOnLead() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.ace, .spades)],
                [
                    card(.bigJoker, nil),
                    card(.six, .hearts),
                    card(.six, .diamonds),
                    card(.nine, .hearts),
                    card(.jack, .hearts)
                ],
                [card(.three), card(.four), card(.five)],
                [card(.seven), card(.eight), card(.ten)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let combination = RulesEngine.classify(action.cards)
        #expect(combination?.kind == .pair)
    }

    @Test("AI uses a non-single bomb over a single two to block a one-card opponent")
    func aiBlocksOneCardOpponentOnFollow() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.four), card(.five), card(.six), card(.seven)],
                [
                    card(.two, .hearts),
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .clubs),
                    card(.eight, .hearts),
                    card(.nine, .hearts)
                ],
                [card(.bigJoker, nil)],
                [card(.ten), card(.jack), card(.queen)]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.king, .clubs)], primaryRank: .king),
                kind: .normal,
                message: "Human出单张"
            ),
            cardsPlayedCount: [13, 10, 12, 8]
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let combination = RulesEngine.classify(action.cards)
        #expect(combination?.kind == .sameRankBomb)
        #expect(combination?.primaryRank == .three)
    }

    @Test("AI chooses legal actions promptly for multi deck opening hands")
    func aiChoosesPromptlyForMultiDeckOpeningHands() throws {
        let ai = AIPlayer()

        for deckCount in 2...4 {
            let deck = DeckConfig(deckCount: deckCount).makeDeck()
            let engine = GameEngine(deckCount: deckCount, deck: deck)
            let playerIndex = try #require(engine.state.prompt.playerIndex)

            let start = Date()
            let action = ai.chooseAction(state: engine.state, for: playerIndex)
            let elapsed = Date().timeIntervalSince(start)

            #expect(engine.legalActions(for: playerIndex).contains(action))
            #expect(elapsed < 1.5, "\(deckCount) decks took \(elapsed)s")
        }
    }

    @Test("AI chooses legal follow actions promptly for multi deck hands")
    func aiChoosesPromptlyForMultiDeckFollowHands() throws {
        let ai = AIPlayer()

        for deckCount in 2...4 {
            var hands = GameEngine.deal(
                deck: DeckConfig(deckCount: deckCount).makeDeck(),
                playerCount: Self.players.count
            )
            let previousIndex = try #require(hands[0].firstIndex { $0.rank == .three })
            let previousCard = hands[0].remove(at: previousIndex)
            let state = GameState(
                deckCount: deckCount,
                players: Self.players,
                hands: hands,
                prompt: TurnPrompt(kind: .follow, playerIndex: 1),
                lastPlayableRecord: PlayRecord(
                    playerIndex: 0,
                    playerName: "Human",
                    combination: Combination(kind: .single, cards: [previousCard], primaryRank: .three),
                    kind: .normal,
                    message: "Human出单张"
                )
            )

            let start = Date()
            let action = ai.chooseAction(state: state, for: 1)
            let elapsed = Date().timeIntervalSince(start)

            #expect(ai.legalActions(from: state, for: 1).contains(action))
            #expect(elapsed < 1.5, "\(deckCount) decks follow took \(elapsed)s")
        }
    }

    private static let players = [
        GamePlayer(name: "Human", isHuman: true),
        GamePlayer(name: "AI1", isHuman: false),
        GamePlayer(name: "AI2", isHuman: false),
        GamePlayer(name: "AI3", isHuman: false)
    ]
}

private extension Array where Element == Card {
    func removingForTest(_ cards: [Card]) -> [Card] {
        var remaining = self
        for card in cards {
            if let index = remaining.firstIndex(of: card) {
                remaining.remove(at: index)
            }
        }
        return remaining
    }
}
