import Foundation
import Testing
@testable import FourFourteenCore

private func gdCard(_ rank: Rank, _ suit: Suit? = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("GuanDan")
struct GuanDanTests {
    @Test("red heart level card can complete a straight flush")
    func wildCompletesStraightFlush() throws {
        let combo = try #require(GuanDanRulesEngine.classify([
            gdCard(.five, .hearts),
            gdCard(.six, .hearts),
            gdCard(.seven, .hearts),
            gdCard(.eight, .hearts),
            gdCard(.two, .hearts)
        ]))

        #expect(combo.kind == .straightFlush)
        #expect(combo.primaryRank == .nine)
        #expect(combo.usesWildCards)
    }

    @Test("guandan bomb hierarchy follows common single-hand rules")
    func bombHierarchy() throws {
        let fourBomb = try #require(GuanDanRulesEngine.classify(Self.sameRank(.three, count: 4)))
        let fiveBomb = try #require(GuanDanRulesEngine.classify(Self.sameRank(.four, count: 5)))
        let sixBomb = try #require(GuanDanRulesEngine.classify(Self.sameRank(.five, count: 6)))
        let straightFlush = try #require(GuanDanRulesEngine.classify([
            gdCard(.six, .spades),
            gdCard(.seven, .spades),
            gdCard(.eight, .spades),
            gdCard(.nine, .spades),
            gdCard(.ten, .spades)
        ]))
        let jokerBomb = try #require(GuanDanRulesEngine.classify([
            gdCard(.smallJoker, nil, deck: 0),
            gdCard(.smallJoker, nil, deck: 1),
            gdCard(.bigJoker, nil, deck: 0),
            gdCard(.bigJoker, nil, deck: 1)
        ]))

        #expect(GuanDanRulesEngine.canBeat(fiveBomb, fourBomb))
        #expect(GuanDanRulesEngine.canBeat(straightFlush, fiveBomb))
        #expect(GuanDanRulesEngine.canBeat(sixBomb, straightFlush))
        #expect(GuanDanRulesEngine.canBeat(jokerBomb, sixBomb))
    }

    @Test("AI usually does not beat teammate unless finishing")
    func aiDoesNotBeatTeammate() {
        let teammatePair = [gdCard(.five, .clubs), gdCard(.five, .diamonds)]
        let state = GuanDanState(
            players: Self.players,
            hands: [
                [],
                [],
                [
                    gdCard(.six, .clubs),
                    gdCard(.six, .diamonds),
                    gdCard(.seven, .clubs),
                    gdCard(.eight, .clubs),
                    gdCard(.nine, .clubs)
                ],
                []
            ],
            currentPlayerIndex: 2,
            lastPlay: GuanDanPlayRecord(
                playerIndex: 0,
                playerName: "你",
                combination: GuanDanCombination(kind: .pair, cards: teammatePair, primaryRank: .five),
                kind: .play,
                message: "你出对子"
            )
        )

        let action = GuanDanAIPlayer().chooseAction(state: state, for: 2)
        #expect(action == .pass)
    }

    @Test("AI can beat teammate to finish")
    func aiCanBeatTeammateToFinish() {
        let pairSix = [gdCard(.six, .clubs), gdCard(.six, .diamonds)]
        let state = GuanDanState(
            players: Self.players,
            hands: [
                [],
                [],
                pairSix,
                []
            ],
            currentPlayerIndex: 2,
            lastPlay: GuanDanPlayRecord(
                playerIndex: 0,
                playerName: "你",
                combination: GuanDanCombination(
                    kind: .pair,
                    cards: [gdCard(.five, .clubs), gdCard(.five, .diamonds)],
                    primaryRank: .five
                ),
                kind: .play,
                message: "你出对子"
            )
        )

        let action = GuanDanAIPlayer().chooseAction(state: state, for: 2)
        #expect(Set(action.cards) == Set(pairSix))
    }

    @Test("pass round clears the active challenge and allows a lower lead")
    func passRoundAllowsLowerLead() throws {
        let engine = GuanDanGameEngine(
            players: Self.players,
            hands: [
                [gdCard(.three), gdCard(.five)],
                [gdCard(.three, .clubs)],
                [gdCard(.four)],
                [gdCard(.four, .clubs)]
            ],
            startingPlayer: 0
        )

        try engine.apply(.play([gdCard(.five)]))
        try engine.apply(.pass)
        try engine.apply(.pass)
        try engine.apply(.pass)

        #expect(engine.state.currentPlayerIndex == 0)
        #expect(engine.state.lastPlay == nil)
        #expect(!engine.legalActions(for: 0).contains(.pass))

        try engine.apply(.play([gdCard(.three)]))
        #expect(engine.state.lastPlay?.combination?.primaryRank == .three)
    }

    @Test("AI self play finishes shuffled guandan rounds")
    func aiSelfPlayFinishes() throws {
        let ai = GuanDanAIPlayer()
        for seed in 0..<12 {
            let deck = DeckConfig(deckCount: 2).makeDeck().deterministicallyShuffledForGuanDan(seed: seed)
            let engine = GuanDanGameEngine(deck: deck)
            var steps = 0
            while !engine.state.isGameOver && steps < 520 {
                let player = engine.state.currentPlayerIndex
                let action = ai.chooseAction(state: engine.state, for: player)
                #expect(engine.legalActions(for: player).contains(action), "illegal action at seed \(seed), step \(steps)")
                try engine.apply(action)
                steps += 1
            }
            #expect(engine.state.isGameOver, "seed \(seed) did not finish")
        }
    }

    private static let players = [
        GuanDanPlayer(name: "你", isHuman: true),
        GuanDanPlayer(name: "AI 左", isHuman: false),
        GuanDanPlayer(name: "AI 上", isHuman: false),
        GuanDanPlayer(name: "AI 右", isHuman: false)
    ]

    private static func sameRank(_ rank: Rank, count: Int) -> [Card] {
        var cards: [Card] = []
        for deck in 0..<2 {
            for suit in Suit.allCases {
                cards.append(gdCard(rank, suit, deck: deck))
                if cards.count == count {
                    return cards
                }
            }
        }
        return cards
    }
}

private extension Array where Element == Card {
    func deterministicallyShuffledForGuanDan(seed: Int) -> [Card] {
        var generator = GuanDanSeededGenerator(seed: UInt64(seed + 101))
        return shuffled(using: &generator)
    }
}

private struct GuanDanSeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x0F0E_0D0C_0B0A_0908 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
