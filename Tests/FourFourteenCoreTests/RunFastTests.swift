import Foundation
import Testing
@testable import FourFourteenCore

private func rfCard(_ rank: Rank, _ suit: Suit = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("RunFast")
struct RunFastTests {
    @Test("recognizes core run fast combinations")
    func recognizesCombinations() throws {
        let straight = try #require(RunFastRulesEngine.classify([
            rfCard(.three),
            rfCard(.four),
            rfCard(.five),
            rfCard(.six),
            rfCard(.seven)
        ]))
        #expect(straight.kind == .singleStraight)
        #expect(straight.sequenceLength == 5)

        let pairRun = try #require(RunFastRulesEngine.classify([
            rfCard(.seven, .hearts),
            rfCard(.seven, .clubs),
            rfCard(.eight, .hearts),
            rfCard(.eight, .clubs)
        ]))
        #expect(pairRun.kind == .pairStraight)

        let trioWithTwo = try #require(RunFastRulesEngine.classify([
            rfCard(.nine, .hearts),
            rfCard(.nine, .clubs),
            rfCard(.nine, .spades),
            rfCard(.three, .clubs),
            rfCard(.king, .diamonds)
        ]))
        #expect(trioWithTwo.kind == .trioWithTwo)
        #expect(trioWithTwo.primaryRank == .nine)
    }

    @Test("bomb beats ordinary combinations but lower bomb cannot beat higher bomb")
    func bombComparison() throws {
        let bomb = try #require(RunFastRulesEngine.classify([
            rfCard(.four, .hearts),
            rfCard(.four, .diamonds),
            rfCard(.four, .clubs),
            rfCard(.four, .spades)
        ]))
        let straight = try #require(RunFastRulesEngine.classify([
            rfCard(.eight, .hearts),
            rfCard(.nine, .hearts),
            rfCard(.ten, .hearts),
            rfCard(.jack, .hearts),
            rfCard(.queen, .hearts)
        ]))
        let higherBomb = try #require(RunFastRulesEngine.classify([
            rfCard(.six, .hearts),
            rfCard(.six, .diamonds),
            rfCard(.six, .clubs),
            rfCard(.six, .spades)
        ]))

        #expect(RunFastRulesEngine.canBeat(bomb, straight))
        #expect(RunFastRulesEngine.canBeat(higherBomb, bomb))
        #expect(!RunFastRulesEngine.canBeat(bomb, higherBomb))
    }

    @Test("first play must include spade three")
    func firstPlayMustIncludeSpadeThree() throws {
        let players = Self.players
        let spadeThree = rfCard(.three, .spades)
        let engine = RunFastGameEngine(
            players: players,
            hands: [
                [spadeThree, rfCard(.four), rfCard(.five), rfCard(.six), rfCard(.seven)],
                [rfCard(.eight)],
                [rfCard(.nine)]
            ],
            startingPlayer: 0
        )
        #expect(engine.legalActions(for: 0).allSatisfy { $0.cards.contains(spadeThree) })
        #expect(throws: RunFastError.firstPlayMustContainSpadeThree) {
            try engine.apply(.play([rfCard(.four)]))
        }
    }

    @Test("two passes clear the active challenge and allow a lower lead")
    func passRoundAllowsLowerLead() throws {
        let engine = RunFastGameEngine(
            players: Self.players,
            hands: [
                [rfCard(.three), rfCard(.five)],
                [rfCard(.three, .clubs)],
                [rfCard(.four)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([rfCard(.five)]))
        try engine.apply(.pass)
        try engine.apply(.pass)

        #expect(engine.state.currentPlayerIndex == 0)
        #expect(engine.state.lastPlay == nil)
        #expect(!engine.legalActions(for: 0).contains(.pass))

        try engine.apply(.play([rfCard(.three)]))
        #expect(engine.state.lastPlay?.combination?.primaryRank == .three)
    }

    @Test("AI chooses a legal action")
    func aiChoosesLegalAction() {
        let engine = RunFastGameEngine()
        let playerIndex = engine.state.currentPlayerIndex
        let ai = RunFastAIPlayer()
        let action = ai.chooseAction(state: engine.state, for: playerIndex)
        #expect(engine.legalActions(for: playerIndex).contains(action))
    }

    @Test("AI self play finishes multiple shuffled games")
    func aiSelfPlayFinishes() throws {
        let ai = RunFastAIPlayer()
        for seed in 0..<30 {
            var deck = RunFastGameEngine.playableDeck().deterministicallyShuffled(seed: seed)
            let engine = RunFastGameEngine(deck: deck)
            var steps = 0
            while !engine.state.isGameOver && steps < 240 {
                let player = engine.state.currentPlayerIndex
                let action = ai.chooseAction(state: engine.state, for: player)
                #expect(engine.legalActions(for: player).contains(action), "illegal action at seed \(seed), step \(steps)")
                try engine.apply(action)
                steps += 1
                deck.removeAll(keepingCapacity: true)
            }
            #expect(engine.state.isGameOver, "seed \(seed) did not finish")
        }
    }

    private static let players = [
        RunFastPlayer(name: "你", isHuman: true),
        RunFastPlayer(name: "AI 左", isHuman: false),
        RunFastPlayer(name: "AI 右", isHuman: false)
    ]
}

private extension Array where Element == Card {
    func deterministicallyShuffled(seed: Int) -> [Card] {
        var generator = SeededGenerator(seed: UInt64(seed + 1))
        return shuffled(using: &generator)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
