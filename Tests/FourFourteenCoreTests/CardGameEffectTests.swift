import Testing
@testable import FourFourteenCore

private func ecard(_ rank: Rank, _ suit: Suit? = .hearts, deck: Int = 0) -> Card {
    Card(rank: rank, suit: suit, deckIndex: deck)
}

@Suite("CardGameEffectMapper")
struct CardGameEffectTests {
    @Test("414 special combinations map to table effects")
    func mapsFourFourteenEffects() throws {
        let rocket = PlayRecord(
            playerIndex: 2,
            playerName: "AI 上",
            combination: Combination(
                kind: .rocket414,
                cards: [ecard(.four), ecard(.four, .spades), ecard(.ace)],
                primaryRank: .ace
            ),
            kind: .normal,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: rocket)?.kind == .rocket)
        #expect(CardGameEffectMapper.effect(for: rocket)?.intensity == .s)

        let doubleJoker = PlayRecord(
            playerIndex: 1,
            playerName: "AI 左",
            combination: Combination(
                kind: .doubleJoker,
                cards: [ecard(.smallJoker, nil), ecard(.bigJoker, nil)],
                primaryRank: .bigJoker
            ),
            kind: .normal,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: doubleJoker)?.kind == .mushroom)

        let bomb = PlayRecord(
            playerIndex: 3,
            playerName: "AI 右",
            combination: Combination(
                kind: .sameRankBomb,
                cards: [ecard(.six), ecard(.six, .spades), ecard(.six, .clubs)],
                primaryRank: .six,
                sameRankCount: 3
            ),
            kind: .normal,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: bomb)?.kind == .bomb)
        #expect(CardGameEffectMapper.effect(for: bomb)?.intensity == .a)

        let singleRun = PlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: Combination(
                kind: .singleRun,
                cards: [ecard(.three), ecard(.four), ecard(.five)],
                primaryRank: .five,
                sequenceLength: 3
            ),
            kind: .normal,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: singleRun)?.kind == .straightTrail)

        let pairRun = PlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: Combination(
                kind: .pairRun,
                cards: [
                    ecard(.three), ecard(.three, .spades),
                    ecard(.four), ecard(.four, .spades),
                    ecard(.five), ecard(.five, .spades)
                ],
                primaryRank: .five,
                sequenceLength: 3
            ),
            kind: .normal,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: pairRun)?.kind == .pairChain)

        let cha = PlayRecord(playerIndex: 1, playerName: "AI 左", combination: nil, kind: .cha, message: "叉")
        #expect(CardGameEffectMapper.effect(for: cha)?.kind == .stamp)

        let single = PlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: Combination(kind: .single, cards: [ecard(.ace)], primaryRank: .ace),
            kind: .normal,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: single) == nil)

        let pass = PlayRecord(playerIndex: 0, playerName: "你", combination: nil, kind: .pass, message: "过")
        #expect(CardGameEffectMapper.effect(for: pass) == nil)
    }

    @Test("dou dizhu special combinations map to table effects")
    func mapsDouDizhuEffects() throws {
        let airplane = DouDizhuPlayRecord(
            playerIndex: 2,
            playerName: "下家",
            combination: DouDizhuCombination(
                kind: .airplaneWithSingles,
                cards: [
                    ecard(.three), ecard(.three, .clubs), ecard(.three, .spades),
                    ecard(.four), ecard(.four, .clubs), ecard(.four, .spades),
                    ecard(.seven), ecard(.eight)
                ],
                primaryRank: .four,
                sequenceLength: 2
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: airplane)?.kind == .airplane)
        #expect(CardGameEffectMapper.effect(for: airplane)?.intensity == .b)

        let pairStraight = DouDizhuPlayRecord(
            playerIndex: 1,
            playerName: "上家",
            combination: DouDizhuCombination(
                kind: .pairStraight,
                cards: [ecard(.five), ecard(.five, .clubs), ecard(.six), ecard(.six, .clubs), ecard(.seven), ecard(.seven, .clubs)],
                primaryRank: .seven,
                sequenceLength: 3
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: pairStraight)?.kind == .pairChain)

        let bomb = DouDizhuPlayRecord(
            playerIndex: 1,
            playerName: "上家",
            combination: DouDizhuCombination(
                kind: .bomb,
                cards: [ecard(.nine), ecard(.nine, .clubs), ecard(.nine, .spades), ecard(.nine, .diamonds)],
                primaryRank: .nine
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: bomb)?.kind == .bomb)

        let rocket = DouDizhuPlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: DouDizhuCombination(
                kind: .rocket,
                cards: [ecard(.smallJoker, nil), ecard(.bigJoker, nil)],
                primaryRank: .bigJoker
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: rocket)?.kind == .mushroom)
        #expect(CardGameEffectMapper.effect(for: rocket)?.intensity == .s)
    }

    @Test("run fast special combinations map to table effects")
    func mapsRunFastEffects() throws {
        let airplane = RunFastPlayRecord(
            playerIndex: 1,
            playerName: "AI 左",
            combination: RunFastCombination(
                kind: .airplaneWithWings,
                cards: [
                    ecard(.six), ecard(.six, .clubs), ecard(.six, .spades),
                    ecard(.seven), ecard(.seven, .clubs), ecard(.seven, .spades),
                    ecard(.nine), ecard(.ten)
                ],
                primaryRank: .seven,
                sequenceLength: 2
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: airplane)?.kind == .airplane)

        let straight = RunFastPlayRecord(
            playerIndex: 2,
            playerName: "AI 右",
            combination: RunFastCombination(
                kind: .singleStraight,
                cards: [ecard(.three), ecard(.four), ecard(.five), ecard(.six), ecard(.seven)],
                primaryRank: .seven,
                sequenceLength: 5
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: straight)?.kind == .straightTrail)

        let single = RunFastPlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: RunFastCombination(kind: .single, cards: [ecard(.king)], primaryRank: .king),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: single) == nil)
    }

    @Test("guandan special combinations map to table effects")
    func mapsGuanDanEffects() throws {
        let steelPlate = GuanDanPlayRecord(
            playerIndex: 2,
            playerName: "AI 上",
            combination: GuanDanCombination(
                kind: .steelPlate,
                cards: [
                    ecard(.three), ecard(.three, .clubs), ecard(.three, .spades),
                    ecard(.four), ecard(.four, .clubs), ecard(.four, .spades)
                ],
                primaryRank: .four,
                sequenceLength: 2
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: steelPlate)?.kind == .steelPlate)

        let straightFlush = GuanDanPlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: GuanDanCombination(
                kind: .straightFlush,
                cards: [ecard(.five), ecard(.six), ecard(.seven), ecard(.eight), ecard(.nine)],
                primaryRank: .nine,
                sequenceLength: 5
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: straightFlush)?.kind == .straightFlush)

        let fourBomb = GuanDanPlayRecord(
            playerIndex: 1,
            playerName: "AI 左",
            combination: GuanDanCombination(
                kind: .bomb,
                cards: [ecard(.queen), ecard(.queen, .clubs), ecard(.queen, .spades), ecard(.queen, .diamonds)],
                primaryRank: .queen,
                bombCount: 4
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: fourBomb)?.kind == .bomb)

        let bigBomb = GuanDanPlayRecord(
            playerIndex: 3,
            playerName: "AI 右",
            combination: GuanDanCombination(
                kind: .bomb,
                cards: [
                    ecard(.ace), ecard(.ace, .clubs), ecard(.ace, .spades), ecard(.ace, .diamonds),
                    ecard(.ace, .hearts, deck: 1), ecard(.ace, .spades, deck: 1)
                ],
                primaryRank: .ace,
                bombCount: 6
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: bigBomb)?.kind == .mushroom)

        let jokerBomb = GuanDanPlayRecord(
            playerIndex: 0,
            playerName: "你",
            combination: GuanDanCombination(
                kind: .jokerBomb,
                cards: [
                    ecard(.smallJoker, nil), ecard(.bigJoker, nil),
                    ecard(.smallJoker, nil, deck: 1), ecard(.bigJoker, nil, deck: 1)
                ],
                primaryRank: .bigJoker
            ),
            kind: .play,
            message: ""
        )
        #expect(CardGameEffectMapper.effect(for: jokerBomb)?.kind == .mushroom)
        #expect(CardGameEffectMapper.effect(for: jokerBomb)?.intensity == .s)
    }
}
