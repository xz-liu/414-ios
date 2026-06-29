import Foundation
import Testing
@testable import FourFourteenCore

private func c(_ rank: Rank, _ suit: Suit? = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("PublicCardMemory")
struct PublicCardMemoryTests {
    @Test("three visible fours rule out opponent 4A4 and four bombs in one deck")
    func visibleFoursRuleOutRocket414() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [c(.seven), c(.eight), c(.nine)],
                [c(.five), c(.six)],
                [c(.ten), c(.jack), c(.queen)],
                [c(.king), c(.ace), c(.three)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1),
            eventLog: [
                Self.record([
                    c(.four, .diamonds),
                    c(.four, .clubs),
                    c(.four, .hearts)
                ])
            ]
        )

        let memory = PublicCardMemory(state: state, playerIndex: 1)

        #expect(memory.opponentAvailableCount(.four) == 1)
        #expect(memory.opponentsCanHaveRocket414 == false)
        #expect(memory.opponentsCanHaveSameRankBomb(rank: .four, count: 3) == false)
        #expect(memory.opponentsCanHaveSameRankBomb(rank: .four, count: 4) == false)
    }

    @Test("visible joker rules out opponent double joker")
    func visibleJokerRulesOutDoubleJoker() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [c(.seven), c(.eight)],
                [c(.five), c(.six)],
                [c(.ten), c(.jack)],
                [c(.queen), c(.king)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1),
            eventLog: [
                Self.record([c(.smallJoker, nil)])
            ]
        )

        let memory = PublicCardMemory(state: state, playerIndex: 1)

        #expect(memory.opponentAvailableCount(.smallJoker) == 0)
        #expect(memory.opponentAvailableCount(.bigJoker) == 1)
        #expect(memory.opponentsCanHaveDoubleJoker == false)
    }

    @Test("visible and own cards exhaust rank potential")
    func visibleAndOwnCardsExhaustRankPotential() {
        let state = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [c(.seven), c(.eight)],
                [c(.nine, .spades)],
                [c(.ten), c(.jack)],
                [c(.queen), c(.king)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1),
            eventLog: [
                Self.record([
                    c(.nine, .diamonds),
                    c(.nine, .clubs),
                    c(.nine, .hearts)
                ])
            ]
        )

        let memory = PublicCardMemory(state: state, playerIndex: 1)

        #expect(memory.opponentAvailableCount(.nine) == 0)
        #expect(memory.rankExhausted(.nine))
        #expect(memory.opponentsCanCha(rank: .nine) == false)
        #expect(memory.opponentsCanGou(rank: .nine) == false)
    }

    @Test("memory does not inspect hidden opponent card identities")
    func memoryDoesNotInspectHiddenOpponentCards() {
        let ownHand = [c(.five), c(.six)]
        let stateWithHiddenRocket = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [c(.four, .diamonds), c(.four, .clubs), c(.ace, .spades)],
                ownHand,
                [c(.seven), c(.eight), c(.nine)],
                [c(.ten), c(.jack), c(.queen)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )
        let stateWithoutHiddenRocket = GameState(
            deckCount: 1,
            players: Self.players,
            hands: [
                [c(.seven), c(.eight), c(.nine)],
                ownHand,
                [c(.ten), c(.jack), c(.queen)],
                [c(.king), c(.three), c(.five, .diamonds)]
            ],
            prompt: TurnPrompt(kind: .lead, playerIndex: 1)
        )

        let memoryA = PublicCardMemory(state: stateWithHiddenRocket, playerIndex: 1)
        let memoryB = PublicCardMemory(state: stateWithoutHiddenRocket, playerIndex: 1)

        #expect(memoryA.opponentAvailableCount(.four) == memoryB.opponentAvailableCount(.four))
        #expect(memoryA.opponentAvailableCount(.ace) == memoryB.opponentAvailableCount(.ace))
        #expect(memoryA.opponentsCanHaveRocket414 == memoryB.opponentsCanHaveRocket414)
        #expect(memoryA.opponentsCanHaveDoubleJoker == memoryB.opponentsCanHaveDoubleJoker)
    }

    private static let players = [
        GamePlayer(name: "Human", isHuman: true),
        GamePlayer(name: "AI1", isHuman: false),
        GamePlayer(name: "AI2", isHuman: false),
        GamePlayer(name: "AI3", isHuman: false)
    ]

    private static func record(_ cards: [Card]) -> PlayRecord {
        PlayRecord(
            playerIndex: 0,
            playerName: "Human",
            combination: RulesEngine.classify(cards),
            kind: .normal,
            message: "Human out"
        )
    }
}
