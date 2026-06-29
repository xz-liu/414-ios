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

    @Test("deals three-player games for one to three decks")
    func dealsThreePlayerGames() throws {
        for deckCount in 1...3 {
            let deck = DeckConfig(deckCount: deckCount).makeDeck()
            let engine = GameEngine(deckCount: deckCount, deck: deck, playerCount: 3)
            let starter = try #require(GameEngine.findHeartThreeHolder(in: engine.state.hands))

            #expect(engine.state.players.map(\.name) == ["你", "AI 左", "AI 右"])
            #expect(engine.state.hands.map(\.count) == Array(repeating: 18 * deckCount, count: 3))
            #expect(Set(engine.state.hands.flatMap { $0 }.map(\.id)).count == deckCount * 54)
            #expect(engine.state.prompt.kind == .lead)
            #expect(engine.state.prompt.playerIndex == starter)
        }
    }

    @Test("three passes return lead to the last player who played")
    func threePassesResetLead() throws {
        let engine = GameEngine(
            players: Self.players,
            hands: [
                [card(.four), card(.five), card(.nine)],
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
        #expect(engine.state.lastPlayableRecord == nil)

        try engine.apply(.play([card(.four)]))
        #expect(engine.state.lastPlayableRecord?.combination?.primaryRank == .four)
    }

    @Test("two passes return lead in a three-player game")
    func twoPassesResetLeadInThreePlayerGame() throws {
        let engine = GameEngine(
            players: Self.threePlayers,
            hands: [
                [card(.four), card(.five), card(.nine)],
                [card(.six)],
                [card(.seven)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([card(.five)]))
        try engine.apply(.pass)
        try engine.apply(.pass)

        #expect(engine.state.prompt.kind == .lead)
        #expect(engine.state.prompt.playerIndex == 0)
        #expect(engine.state.lastPlayableRecord == nil)
        #expect(engine.state.eventLog.last?.message == "2家过牌，Human重新起手")

        try engine.apply(.play([card(.four)]))
        #expect(engine.state.lastPlayableRecord?.combination?.primaryRank == .four)
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

    @Test("three-player dead cha gives lead to cha player")
    func threePlayerDeadChaTransfersLead() throws {
        let engine = GameEngine(
            players: Self.threePlayers,
            hands: [
                [card(.five, .hearts), card(.nine)],
                [card(.five, .diamonds), card(.five, .clubs), card(.eight)],
                [card(.five, .spades), card(.six)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([card(.five, .hearts)]))
        #expect(engine.state.prompt.kind == .cha)
        #expect(engine.state.prompt.playerIndex == 1)

        try engine.apply(.cha([card(.five, .diamonds), card(.five, .clubs)]))
        #expect(engine.state.prompt.kind == .gou)
        #expect(engine.state.prompt.playerIndex == 2)

        try engine.apply(.pass)

        #expect(engine.state.prompt.kind == .lead)
        #expect(engine.state.prompt.playerIndex == 1)
        #expect(engine.state.lastPlayableRecord == nil)
        #expect(engine.state.eventLog.last?.message == "无人勾，AI 左死叉后起手")
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

    @Test("AI saves a bomb when the table shape already covers the short-card threat")
    func aiSavesBombWhenCurrentTableShapeCoversThreat() {
        let previous = Combination(
            kind: .pair,
            cards: [card(.queen, .hearts), card(.queen, .clubs)],
            primaryRank: .queen
        )
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.ace, .spades)],
                [
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.eight, .hearts),
                    card(.nine, .hearts)
                ],
                [card(.three, .clubs), card(.four, .clubs), card(.five, .clubs)],
                [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .spades),
                    card(.eight, .clubs),
                    card(.nine, .clubs)
                ]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 3),
            lastPlayableRecord: PlayRecord(
                playerIndex: 2,
                playerName: "AI2",
                combination: previous,
                kind: .normal,
                message: "AI2出对子"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 3)
        #expect(action == .pass)
    }

    @Test("AI uses a bomb when it is the last reliable interception point")
    func aiUsesBombWhenNoReliableInterceptorRemains() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.ace, .spades)],
                [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .spades),
                    card(.eight, .clubs),
                    card(.nine, .clubs)
                ],
                [card(.four, .clubs)],
                [card(.five, .clubs)]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(
                    kind: .pair,
                    cards: [card(.king, .hearts), card(.king, .clubs)],
                    primaryRank: .king
                ),
                kind: .normal,
                message: "Human出对子"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let combination = RulesEngine.classify(action.cards)
        #expect(combination?.kind == .sameRankBomb)
        #expect(combination?.primaryRank == .three)
    }

    @Test("AI chooses the lowest sufficient interception over a bomb")
    func aiPrefersOrdinaryInterceptionOverBomb() {
        let pairAces = [card(.ace, .hearts), card(.ace, .clubs)]
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.nine, .spades)],
                pairAces + [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .spades),
                    card(.five, .clubs)
                ],
                [card(.four, .clubs)],
                [card(.five, .clubs)]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(
                    kind: .pair,
                    cards: [card(.king, .hearts), card(.king, .clubs)],
                    primaryRank: .king
                ),
                kind: .normal,
                message: "Human出对子"
            )
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(Set(action.cards) == Set(pairAces))
    }

    @Test("AI leads a three-or-more-card shape when an opponent has two cards")
    func aiRestrictsTwoCardOpponentOnLead() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.ace, .spades), card(.king, .spades)],
                [
                    card(.three, .hearts),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.six, .clubs),
                    card(.nine, .clubs)
                ],
                [card(.four, .clubs), card(.five, .clubs), card(.six, .clubs)],
                [card(.seven, .clubs), card(.eight, .clubs), card(.nine, .clubs)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        #expect(action.cards.count >= 3)
        #expect(RulesEngine.classify(action.cards)?.kind == .singleRun)
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

    @Test("three-deck AI does not open with 4A4 when ordinary lead shapes are available")
    func threeDeckAIDoesNotOpenWithRocket414() throws {
        let aiHand = [
            card(.three, .hearts, deck: 1),
            card(.four, .hearts),
            card(.four, .diamonds),
            card(.five, .clubs),
            card(.six, .clubs),
            card(.seven, .clubs),
            card(.eight, .clubs),
            card(.nine, .clubs),
            card(.ten, .clubs),
            card(.jack, .diamonds),
            card(.queen, .diamonds),
            card(.ace, .spades),
            card(.two, .clubs),
            card(.smallJoker, nil, deck: 1)
        ]
        let aiHandSet = Set(aiHand)
        let filler = DeckConfig(deckCount: 3).makeDeck().filter { !aiHandSet.contains($0) }
        let state = GameState(
            deckCount: 3,
            players: Self.players,
            hands: [
                Array(filler[0..<28]),
                aiHand,
                Array(filler[28..<56]),
                Array(filler[56..<84])
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let ai = AIPlayer()
        let action = ai.chooseAction(state: state, for: 1)
        let combination = try #require(RulesEngine.classify(action.cards))

        #expect(ai.legalActions(from: state, for: 1).contains(action))
        #expect(combination.kind != .rocket414)
    }

    @Test("multi-deck AI spends abundant control before the one-card cliff")
    func multiDeckAIUsesAbundantControlEarlier() {
        let state = GameState(
            deckCount: 2,
            players: Self.players,
            hands: [
                [
                    card(.three, .hearts, deck: 1),
                    card(.four, .hearts, deck: 1),
                    card(.five, .hearts, deck: 1),
                    card(.six, .hearts, deck: 1),
                    card(.seven, .hearts, deck: 1),
                    card(.eight, .hearts, deck: 1)
                ],
                [
                    card(.two, .hearts),
                    card(.two, .spades, deck: 1),
                    card(.smallJoker, nil),
                    card(.bigJoker, nil),
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .clubs),
                    card(.four, .hearts),
                    card(.four, .diamonds),
                    card(.four, .clubs),
                    card(.four, .spades),
                    card(.nine, .clubs),
                    card(.ten, .clubs),
                    card(.jack, .clubs)
                ],
                [
                    card(.five, .clubs, deck: 1),
                    card(.six, .clubs, deck: 1),
                    card(.seven, .clubs, deck: 1),
                    card(.eight, .clubs, deck: 1),
                    card(.nine, .clubs, deck: 1),
                    card(.ten, .clubs, deck: 1),
                    card(.jack, .clubs, deck: 1),
                    card(.queen, .clubs, deck: 1)
                ],
                [
                    card(.five, .diamonds, deck: 1),
                    card(.six, .diamonds, deck: 1),
                    card(.seven, .diamonds, deck: 1),
                    card(.eight, .diamonds, deck: 1),
                    card(.nine, .diamonds, deck: 1),
                    card(.ten, .diamonds, deck: 1),
                    card(.jack, .diamonds, deck: 1),
                    card(.queen, .diamonds, deck: 1)
                ]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(
                    kind: .single,
                    cards: [card(.king, .clubs)],
                    primaryRank: .king
                ),
                kind: .normal,
                message: "Human出单张"
            ),
            cardsPlayedCount: [12, 10, 8, 8]
        )

        let ai = AIPlayer()
        let action = ai.chooseAction(state: state, for: 1)
        #expect(ai.legalActions(from: state, for: 1).contains(action))
        #expect(action != .pass)
    }

    @Test("three-deck AI treats three-card bombs as lower-cost pressure")
    func threeDeckAIDoesNotHoardCommonThreeCardBombs() {
        let state = GameState(
            deckCount: 3,
            players: Self.players,
            hands: [
                [
                    card(.four, .hearts, deck: 2),
                    card(.five, .hearts, deck: 2),
                    card(.six, .hearts, deck: 2),
                    card(.seven, .hearts, deck: 2),
                    card(.eight, .hearts, deck: 2),
                    card(.nine, .hearts, deck: 2),
                    card(.ten, .hearts, deck: 2),
                    card(.jack, .hearts, deck: 2)
                ],
                [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .clubs),
                    card(.four, .hearts),
                    card(.four, .diamonds),
                    card(.four, .clubs),
                    card(.five, .hearts),
                    card(.five, .diamonds),
                    card(.five, .clubs),
                    card(.six, .clubs),
                    card(.seven, .clubs),
                    card(.eight, .clubs),
                    card(.nine, .clubs),
                    card(.ten, .clubs)
                ],
                [
                    card(.six, .clubs, deck: 2),
                    card(.seven, .clubs, deck: 2),
                    card(.eight, .clubs, deck: 2),
                    card(.nine, .clubs, deck: 2),
                    card(.ten, .clubs, deck: 2),
                    card(.jack, .clubs, deck: 2),
                    card(.queen, .clubs, deck: 2),
                    card(.king, .clubs, deck: 2),
                    card(.ace, .clubs, deck: 2)
                ],
                [
                    card(.six, .diamonds, deck: 2),
                    card(.seven, .diamonds, deck: 2),
                    card(.eight, .diamonds, deck: 2),
                    card(.nine, .diamonds, deck: 2),
                    card(.ten, .diamonds, deck: 2),
                    card(.jack, .diamonds, deck: 2),
                    card(.queen, .diamonds, deck: 2),
                    card(.king, .diamonds, deck: 2),
                    card(.ace, .diamonds, deck: 2)
                ]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(
                    kind: .pair,
                    cards: [card(.ace, .hearts, deck: 2), card(.ace, .spades, deck: 2)],
                    primaryRank: .ace
                ),
                kind: .normal,
                message: "Human出对子"
            ),
            cardsPlayedCount: [18, 14, 12, 12]
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let combination = RulesEngine.classify(action.cards)
        #expect(combination?.kind == .sameRankBomb)
        #expect(combination?.sameRankCount == 3)
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

    @Test("AI defaults to competitive style")
    func aiDefaultsToCompetitiveStyle() {
        #expect(AIPlayer().style == .competitive)
    }

    @Test("relaxed AI still finishes in one action")
    func relaxedAIStillFinishes() {
        let six = card(.six, .hearts)
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.three), card(.four), card(.five), card(.seven)],
                [six],
                [card(.eight), card(.nine), card(.ten)],
                [card(.jack), card(.queen), card(.king)]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(kind: .single, cards: [card(.five, .clubs)], primaryRank: .five),
                kind: .normal,
                message: "Human出单张"
            )
        )

        #expect(AIPlayer(style: .relaxed).chooseAction(state: state, for: 1) == .play([six]))
    }

    @Test("AI keeps compact control endgames intact instead of splitting a bomb")
    func aiKeepsCompactControlEndgameIntact() throws {
        let aces = [
            card(.ace, .hearts),
            card(.ace, .diamonds),
            card(.ace, .clubs)
        ]
        let hand = aces + [
            card(.smallJoker, nil),
            card(.bigJoker, nil)
        ]
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.three), card(.four), card(.five)],
                hand,
                [card(.six), card(.seven), card(.eight)],
                [card(.nine), card(.ten), card(.jack)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        for style in AIStyle.allCases {
            let action = AIPlayer(style: style).chooseAction(state: state, for: 1)
            let combination = try #require(RulesEngine.classify(action.cards))

            #expect(combination.kind == .sameRankBomb)
            #expect(combination.primaryRank == .ace)
            #expect(Set(action.cards) == Set(aces))
        }
    }

    @Test("AI does not break a same-rank bomb just to make a short run")
    func aiDoesNotBreakBombForShortRun() throws {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [card(.six), card(.seven), card(.eight)],
                [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .clubs),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.nine, .clubs),
                    card(.jack, .clubs),
                    card(.king, .clubs)
                ],
                [card(.six, .diamonds), card(.seven, .diamonds), card(.eight, .diamonds)],
                [card(.six, .spades), card(.seven, .spades), card(.eight, .spades)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let action = AIPlayer().chooseAction(state: state, for: 1)
        let combination = try #require(RulesEngine.classify(action.cards))
        let usesThree = action.cards.contains { $0.rank == .three }

        #expect(!(combination.kind == .singleRun && usesThree))
        #expect(!(combination.kind == .single && combination.primaryRank == .three))
    }

    @Test("relaxed AI passes instead of spending a bomb in low pressure")
    func relaxedAIPassesInsteadOfLowPressureBomb() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [
                    card(.four, .clubs),
                    card(.five, .clubs),
                    card(.six, .clubs),
                    card(.seven, .clubs),
                    card(.eight, .clubs),
                    card(.nine, .clubs)
                ],
                [
                    card(.three, .hearts),
                    card(.three, .diamonds),
                    card(.three, .clubs),
                    card(.four, .hearts),
                    card(.five, .hearts),
                    card(.six, .hearts),
                    card(.seven, .hearts),
                    card(.eight, .hearts)
                ],
                [
                    card(.four, .diamonds),
                    card(.five, .diamonds),
                    card(.six, .diamonds),
                    card(.seven, .diamonds),
                    card(.eight, .diamonds),
                    card(.nine, .diamonds)
                ],
                [
                    card(.four, .spades),
                    card(.five, .spades),
                    card(.six, .spades),
                    card(.seven, .spades),
                    card(.eight, .spades),
                    card(.nine, .spades)
                ]
            ],
            prompt: TurnPrompt(kind: .follow, playerIndex: 1),
            lastPlayableRecord: PlayRecord(
                playerIndex: 0,
                playerName: "Human",
                combination: Combination(
                    kind: .pair,
                    cards: [card(.king, .clubs), card(.king, .diamonds)],
                    primaryRank: .king
                ),
                kind: .normal,
                message: "Human出对子"
            )
        )

        let ai = AIPlayer(style: .relaxed)
        let action = ai.chooseAction(state: state, for: 1)

        #expect(ai.legalActions(from: state, for: 1).contains(action))
        #expect(action == .pass)
    }

    private static let players = [
        GamePlayer(name: "Human", isHuman: true),
        GamePlayer(name: "AI1", isHuman: false),
        GamePlayer(name: "AI2", isHuman: false),
        GamePlayer(name: "AI3", isHuman: false)
    ]

    private static let threePlayers = [
        GamePlayer(name: "Human", isHuman: true),
        GamePlayer(name: "AI 左", isHuman: false),
        GamePlayer(name: "AI 右", isHuman: false)
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
