import { describe, expect, test } from 'vitest';
import { Card, Rank, Suit, makeDeck } from '../core/cards';
import { PublicCardMemory } from '../core/publicMemory';
import { classify414, classifyDouDizhu, classifyGuanDan, classifyRunFast, canBeat414, canBeatDouDizhu, canBeatGuanDan, canBeatRunFast } from '../core/rules';
import { activeChallengeRecordFor as active414Challenge, fourFourteenModule, FourFourteenState } from '../games/fourFourteen';
import { activeChallengeRecordFor as activeDouDizhuChallenge, douDizhuModule, DouDizhuState } from '../games/doudizhu';
import { activeChallengeRecordFor as activeRunFastChallenge, runFastModule, RunFastState } from '../games/runFast';
import { activeChallengeRecordFor as activeGuanDanChallenge, guanDanModule, GuanDanState } from '../games/guanDan';

function c(rank: Rank, suit: Suit = 'H', deck = 0): Card {
  return { id: `${deck}-${suit}-${rank}-${Math.random()}`, rank, suit: rank === 'SJ' || rank === 'BJ' ? 'J' : suit, deck };
}

describe('cards and PWA rules', () => {
  test('deck identities are unique across duplicate decks', () => {
    const deck = makeDeck(3);
    expect(new Set(deck.map((card) => card.id)).size).toBe(deck.length);
    expect(deck).toHaveLength(162);
  });

  test('414 recognizes rockets, double joker, bombs, and public memory impossibility', () => {
    expect(classify414([c('4'), c('4', 'S'), c('A')])?.kind).toBe('rocket414');
    expect(classify414([c('SJ'), c('BJ')])?.kind).toBe('doubleJoker');
    expect(classify414([c('6'), c('6', 'S'), c('6', 'C')])?.kind).toBe('sameRankBomb');

    const memory = new PublicCardMemory({
      deckCount: 1,
      ownCards: [],
      visibleCards: [c('4'), c('4', 'S'), c('4', 'C')]
    });
    expect(memory.opponentsCanHaveRocket414()).toBe(false);
    expect(memory.opponentsCanHaveSameRankBomb('4', 3)).toBe(false);
  });

  test('414 triad attachments and bomb pressure stay distinct', () => {
    const trioWithSingle = classify414([c('3'), c('3', 'S'), c('3', 'C'), c('4')])!;
    const trioWithPair = classify414([c('3'), c('3', 'S'), c('3', 'C'), c('4'), c('4', 'S')])!;
    const fourBomb = classify414([c('3'), c('3', 'S'), c('3', 'C'), c('3', 'D')])!;
    const invalid = classify414([c('3'), c('3', 'S'), c('3', 'C'), c('4'), c('5')]);
    const higherTrioWithSingle = classify414([c('4'), c('4', 'S'), c('4', 'C'), c('5')])!;
    const threeBomb = classify414([c('6'), c('6', 'S'), c('6', 'C')])!;

    expect(trioWithSingle.kind).toBe('trioWithSingle');
    expect(trioWithPair.kind).toBe('trioWithPair');
    expect(fourBomb.kind).toBe('sameRankBomb');
    expect(invalid).toBeUndefined();
    expect(canBeat414(higherTrioWithSingle, trioWithSingle)).toBe(true);
    expect(canBeat414(trioWithPair, trioWithSingle)).toBe(false);
    expect(canBeat414(threeBomb, trioWithSingle)).toBe(false);
    expect(canBeat414(fourBomb, trioWithSingle)).toBe(true);
  });

  test('414 default is 3 players, one deck, relaxed AI', () => {
    const state = fourFourteenModule.deal(fourFourteenModule.create());
    expect(state.players).toHaveLength(3);
    expect(state.players.map((player) => player.hand.length)).toEqual([18, 18, 18]);
    expect(state.settings.aiStyle).toBe('relaxed');
    expect(state.settings.deckCount).toBe(1);
  });

  test('dou dizhu recognizes airplane, rocket, and bomb hierarchy', () => {
    const airplane = classifyDouDizhu([c('3'), c('3', 'S'), c('3', 'C'), c('4'), c('4', 'S'), c('4', 'C'), c('6'), c('7')]);
    expect(airplane?.kind).toBe('airplaneWithSingles');
    const pair = classifyDouDizhu([c('A'), c('A', 'S')])!;
    const bomb = classifyDouDizhu([c('3'), c('3', 'S'), c('3', 'C'), c('3', 'D')])!;
    const rocket = classifyDouDizhu([c('SJ'), c('BJ')])!;
    expect(canBeatDouDizhu(bomb, pair)).toBe(true);
    expect(canBeatDouDizhu(rocket, bomb)).toBe(true);
  });

  test('dou dizhu deal enters bidding with 17 cards plus bottom', () => {
    const state = douDizhuModule.deal(douDizhuModule.create());
    expect(state.phase).toBe('bidding');
    expect(state.players.map((player) => player.hand.length)).toEqual([17, 17, 17]);
    expect(state.bottomCards).toHaveLength(3);
  });

  test('run fast uses 48 cards and black spade three opener', () => {
    const state = runFastModule.deal(runFastModule.create());
    expect(state.players.map((player) => player.hand.length)).toEqual([16, 16, 16]);
    expect(state.players[state.currentPlayerIndex].hand.some((card) => card.rank === '3' && card.suit === 'S')).toBe(true);

    const bomb = classifyRunFast([c('4'), c('4', 'S'), c('4', 'C'), c('4', 'D')])!;
    const straight = classifyRunFast([c('8'), c('9'), c('10'), c('J'), c('Q')])!;
    expect(canBeatRunFast(bomb, straight)).toBe(true);
  });

  test('guan dan recognizes wild straight flush and bomb hierarchy', () => {
    const straightFlush = classifyGuanDan([c('5', 'H'), c('6', 'H'), c('7', 'H'), c('8', 'H'), c('2', 'H')]);
    expect(straightFlush?.kind).toBe('straightFlush');
    expect(straightFlush?.usesWildCards).toBe(true);

    const sixBomb = classifyGuanDan([c('5'), c('5', 'S'), c('5', 'C'), c('5', 'D'), c('5', 'H', 1), c('5', 'S', 1)])!;
    const jokerBomb = classifyGuanDan([c('SJ', 'J', 0), c('SJ', 'J', 1), c('BJ', 'J', 0), c('BJ', 'J', 1)])!;
    expect(canBeatGuanDan(jokerBomb, sixBomb)).toBe(true);
  });

  test('all game modules produce legal human hints after deal when possible', () => {
    const modules = [fourFourteenModule, douDizhuModule, runFastModule, guanDanModule] as Array<{
      create: () => unknown;
      deal: (state: unknown) => unknown;
      view: (state: unknown) => { phase: string };
      isHumanTurn: (state: unknown) => boolean;
      hint: (state: unknown) => Card[];
      legalActions: (state: unknown, selected: Card[]) => string[];
      aiStep: (state: unknown) => unknown;
    }>;
    for (const module of modules) {
      let state = module.deal(module.create());
      for (let step = 0; step < 12; step += 1) {
        const view = module.view(state);
        if (view.phase === 'finished') break;
        if (module.isHumanTurn(state)) {
          const hint = module.hint(state);
          const actions = module.legalActions(state, hint);
          expect(actions.includes('play') || actions.includes('pass') || actions.some((action) => action.startsWith('bid'))).toBe(true);
          break;
        }
        state = module.aiStep(state);
      }
    }
  });

  test('414 pass round clears active challenge and allows lower lead', () => {
    const state: FourFourteenState = {
      key: '414',
      settings: { playerCount: 3, deckCount: 1, aiStyle: 'competitive' },
      phase: 'playing',
      players: [
        { id: 0, name: '你', isHuman: true, hand: [c('3'), c('3', 'S'), c('5'), c('5', 'S')] },
        { id: 1, name: 'AI 左', isHuman: false, hand: [c('4')] },
        { id: 2, name: 'AI 右', isHuman: false, hand: [c('4', 'S')] }
      ],
      currentPlayerIndex: 0,
      tableRecords: [undefined, undefined, undefined],
      passCount: 0,
      message: '',
      scores: [],
      eventLog: [],
      effectSeq: 0
    };
    let next = fourFourteenModule.apply(state, 'play', state.players[0].hand.filter((card) => card.rank === '5'));
    next = fourFourteenModule.aiStep(next);
    next = fourFourteenModule.aiStep(next);

    const lowerPair = next.players[0].hand.filter((card) => card.rank === '3');
    expect(next.currentPlayerIndex).toBe(0);
    expect(active414Challenge(next, 0)).toBeUndefined();
    expect(fourFourteenModule.legalActions(next, lowerPair)).toContain('play');
    expect(fourFourteenModule.legalActions(next, lowerPair)).not.toContain('pass');
  });

  test('414 single without eligible cha continues as normal follow', () => {
    const state: FourFourteenState = {
      key: '414',
      settings: { playerCount: 3, deckCount: 1, aiStyle: 'competitive' },
      phase: 'playing',
      players: [
        { id: 0, name: '你', isHuman: true, hand: [c('3', 'H'), c('9')] },
        { id: 1, name: 'AI 左', isHuman: false, hand: [c('4')] },
        { id: 2, name: 'AI 右', isHuman: false, hand: [c('5')] }
      ],
      currentPlayerIndex: 0,
      tableRecords: [undefined, undefined, undefined],
      passCount: 0,
      message: '',
      scores: [],
      eventLog: [],
      effectSeq: 0
    };
    const next = fourFourteenModule.apply(state, 'play', [state.players[0].hand[0]]);

    expect(next.reaction).toBeUndefined();
    expect(next.currentPlayerIndex).toBe(1);
    expect(active414Challenge(next, 1)?.combo?.kind).toBe('single');
  });

  test('414 declined cha keeps the original single as active challenge', () => {
    const sourceCard = c('7');
    const sourceCombo = classify414([sourceCard])!;
    const sourceRecord = {
      id: 4147,
      playerIndex: 1,
      cards: [sourceCard],
      combo: sourceCombo,
      label: 'AI 左出单张'
    };
    const state: FourFourteenState = {
      key: '414',
      settings: { playerCount: 3, deckCount: 1, aiStyle: 'competitive' },
      phase: 'playing',
      players: [
        { id: 0, name: '你', isHuman: true, hand: [c('7', 'S'), c('7', 'C')] },
        { id: 1, name: 'AI 左', isHuman: false, hand: [c('4')] },
        { id: 2, name: 'AI 右', isHuman: false, hand: [c('8')] }
      ],
      currentPlayerIndex: 0,
      lastPlay: sourceRecord,
      visibleRecord: sourceRecord,
      tableRecords: [undefined, sourceRecord, undefined],
      passCount: 0,
      reaction: { kind: 'cha', targetRank: '7', sourcePlayerIndex: 1, remainingPlayers: [0] },
      message: '',
      scores: [],
      eventLog: [sourceRecord],
      effectSeq: 0
    };

    const next = fourFourteenModule.apply(state, 'pass', []);

    expect(next.reaction).toBeUndefined();
    expect(next.currentPlayerIndex).toBe(2);
    expect(active414Challenge(next, 2)?.combo?.kind).toBe('single');
  });

  test('dou dizhu pass round clears active challenge and allows lower lead', () => {
    const state: DouDizhuState = {
      key: 'doudizhu',
      phase: 'playing',
      players: [
        { id: 0, name: '你', isHuman: true, hand: [c('3'), c('5')] },
        { id: 1, name: 'AI 左', isHuman: false, hand: [c('3', 'S')] },
        { id: 2, name: 'AI 右', isHuman: false, hand: [c('4')] }
      ],
      bottomCards: [],
      currentPlayerIndex: 0,
      highestBid: 1,
      bidTurnCount: 3,
      landlordIndex: 0,
      tableRecords: [undefined, undefined, undefined],
      passCount: 0,
      message: '',
      scores: [],
      effectSeq: 0
    };
    let next = douDizhuModule.apply(state, 'play', [state.players[0].hand[1]]);
    next = douDizhuModule.aiStep(next);
    next = douDizhuModule.aiStep(next);

    expect(next.currentPlayerIndex).toBe(0);
    expect(activeDouDizhuChallenge(next, 0)).toBeUndefined();
    expect(douDizhuModule.legalActions(next, [next.players[0].hand[0]])).toContain('play');
    expect(douDizhuModule.legalActions(next, [next.players[0].hand[0]])).not.toContain('pass');
  });

  test('run fast pass round clears active challenge and allows lower lead', () => {
    const state: RunFastState = {
      key: 'runfast',
      phase: 'playing',
      players: [
        { id: 0, name: '你', isHuman: true, hand: [c('3'), c('5')] },
        { id: 1, name: 'AI 左', isHuman: false, hand: [c('3', 'S')] },
        { id: 2, name: 'AI 右', isHuman: false, hand: [c('4')] }
      ],
      currentPlayerIndex: 0,
      firstPlayDone: true,
      tableRecords: [undefined, undefined, undefined],
      passCount: 0,
      message: '',
      scores: [],
      effectSeq: 0
    };
    let next = runFastModule.apply(state, 'play', [state.players[0].hand[1]]);
    next = runFastModule.aiStep(next);
    next = runFastModule.aiStep(next);

    expect(next.currentPlayerIndex).toBe(0);
    expect(activeRunFastChallenge(next, 0)).toBeUndefined();
    expect(runFastModule.legalActions(next, [next.players[0].hand[0]])).toContain('play');
    expect(runFastModule.legalActions(next, [next.players[0].hand[0]])).not.toContain('pass');
  });

  test('guan dan pass round clears active challenge and allows lower lead', () => {
    const state: GuanDanState = {
      key: 'guandan',
      phase: 'playing',
      players: [
        { id: 0, name: '你', isHuman: true, team: 'A', hand: [c('3'), c('5')] },
        { id: 1, name: 'AI 左', isHuman: false, team: 'B', hand: [c('3', 'S')] },
        { id: 2, name: 'AI 上', isHuman: false, team: 'A', hand: [c('4')] },
        { id: 3, name: 'AI 右', isHuman: false, team: 'B', hand: [c('4', 'S')] }
      ],
      levelRank: '2',
      currentPlayerIndex: 0,
      tableRecords: [undefined, undefined, undefined, undefined],
      passCount: 0,
      message: '',
      scores: [],
      effectSeq: 0
    };
    let next = guanDanModule.apply(state, 'play', [state.players[0].hand[1]]);
    next = guanDanModule.aiStep(next);
    next = guanDanModule.aiStep(next);
    next = guanDanModule.aiStep(next);

    expect(next.currentPlayerIndex).toBe(0);
    expect(activeGuanDanChallenge(next, 0)).toBeUndefined();
    expect(guanDanModule.legalActions(next, [next.players[0].hand[0]])).toContain('play');
    expect(guanDanModule.legalActions(next, [next.players[0].hand[0]])).not.toContain('pass');
  });
});
