import { Card, Rank, containsAllCards, countRank, makeDeck, removeCards, shuffle, sortCards } from '../core/cards';
import { PublicCardMemory } from '../core/publicMemory';
import { Combo, classify414, comboEffect, comboLabel, legal414 } from '../core/rules';
import { chooseAICombo, chooseHintCombo } from './ai';
import { ActionKey, GameModule, GamePhase, PlayerState, TableRecord, TableView, nextActive, tableRecordId } from './types';
import { TableEffect } from '../core/effects';

export type FourFourteenAIStyle = 'relaxed' | 'competitive';

export interface FourFourteenSettings {
  playerCount: 3 | 4;
  deckCount: 1 | 2 | 3;
  aiStyle: FourFourteenAIStyle;
}

interface ReactionState {
  kind: 'cha' | 'gou';
  targetRank: Rank;
  sourcePlayerIndex: number;
  remainingPlayers: number[];
}

export interface FourFourteenState {
  key: '414';
  settings: FourFourteenSettings;
  phase: GamePhase;
  players: PlayerState[];
  currentPlayerIndex: number;
  lastPlay?: TableRecord;
  visibleRecord?: TableRecord;
  tableRecords: Array<TableRecord | undefined>;
  passCount: number;
  reaction?: ReactionState;
  message: string;
  scores: string[];
  eventLog: TableRecord[];
  effect?: TableEffect;
  effectSeq: number;
}

const defaultSettings: FourFourteenSettings = {
  playerCount: 3,
  deckCount: 1,
  aiStyle: 'relaxed'
};

export const fourFourteenModule: GameModule<FourFourteenState> = {
  key: '414',
  title: '414',
  create: () => createFourFourteenState(defaultSettings),
  view,
  deal,
  legalActions,
  apply,
  hint,
  aiStep,
  isHumanTurn: (state) => state.phase !== 'finished' && state.currentPlayerIndex === 0,
  setOption
};

function createFourFourteenState(settings: FourFourteenSettings): FourFourteenState {
  const players = names(settings.playerCount).map<PlayerState>((name, index) => ({
    id: index,
    name,
    isHuman: index === 0,
    hand: [],
    status: index === 0 ? '等待发牌' : '等待'
  }));
  return {
    key: '414',
    settings,
    phase: 'idle',
    players,
    currentPlayerIndex: 0,
    tableRecords: Array(settings.playerCount).fill(undefined),
    passCount: 0,
    message: '点发牌开始',
    scores: [],
    eventLog: [],
    effectSeq: 0
  };
}

function view(state: FourFourteenState): TableView {
  return {
    title: '414',
    subtitle: `${state.settings.playerCount}人 · ${state.settings.deckCount}副 · ${state.settings.aiStyle === 'relaxed' ? '休闲 AI' : '竞技 AI'}`,
    phase: state.phase,
    players: state.players,
    currentPlayerIndex: state.currentPlayerIndex,
    tableRecords: state.tableRecords,
    visibleRecord: state.visibleRecord,
    message: state.message,
    scores: state.scores,
    effect: state.effect,
    settingsSummary: `${state.settings.playerCount}人 / ${state.settings.deckCount}副 / ${state.settings.aiStyle === 'relaxed' ? '休闲' : '竞技'}`
  };
}

function deal(state: FourFourteenState): FourFourteenState {
  const deck = shuffle(makeDeck(state.settings.deckCount));
  const hands = Array.from({ length: state.settings.playerCount }, () => [] as Card[]);
  deck.forEach((card, index) => {
    hands[index % state.settings.playerCount].push(card);
  });
  const players = state.players.map((player, index) => ({
    ...player,
    hand: sortCards(hands[index]),
    finished: false,
    status: '等待'
  }));
  const first = players.findIndex((player) => player.hand.some((card) => card.rank === '3' && card.suit === 'H'));
  players[first].status = '先出';
  return {
    ...state,
    phase: 'playing',
    players,
    currentPlayerIndex: first,
    lastPlay: undefined,
    visibleRecord: undefined,
    tableRecords: Array(state.settings.playerCount).fill(undefined),
    passCount: 0,
    reaction: undefined,
    message: `红桃3在${players[first].name}手中，${players[first].name}先出`,
    scores: [],
    eventLog: [],
    effect: undefined
  };
}

function legalActions(state: FourFourteenState, selected: Card[]): ActionKey[] {
  if (state.phase === 'idle' || state.phase === 'finished') return ['deal'];
  if (state.phase !== 'playing' || state.currentPlayerIndex !== 0) return [];
  const actions: ActionKey[] = ['hint', 'clear'];
  if (state.reaction) {
    actions.push('pass');
    if (state.reaction.kind === 'cha' && canCha(selected, state.reaction.targetRank)) actions.push('cha');
    if (state.reaction.kind === 'gou' && canGou(selected, state.reaction.targetRank)) actions.push('gou');
    return actions;
  }
  const challenge = activeChallengeRecordFor(state, 0);
  const combo = classify414(selected);
  const firstPlay = state.eventLog.length === 0;
  const hasHeartThree = selected.some((card) => card.rank === '3' && card.suit === 'H');
  if (combo && (!challenge || legal414(state.players[0].hand, challenge.combo).some((candidate) => sameCards(candidate.cards, selected)))) {
    if (!firstPlay || hasHeartThree) actions.push('play');
  }
  if (challenge) actions.push('pass');
  return actions;
}

function apply(state: FourFourteenState, action: ActionKey, selected: Card[]): FourFourteenState {
  if (action === 'deal') return deal(state);
  if (state.phase !== 'playing' || state.currentPlayerIndex !== 0) return state;
  if (action === 'pass') return applyPass(state, false);
  if (action === 'cha' && state.reaction?.kind === 'cha' && canCha(selected, state.reaction.targetRank)) {
    return applyReactionPlay(state, selected, 'cha');
  }
  if (action === 'gou' && state.reaction?.kind === 'gou' && canGou(selected, state.reaction.targetRank)) {
    return applyReactionPlay(state, selected, 'gou');
  }
  if (action === 'play') {
    return applyPlay(state, selected);
  }
  return state;
}

function hint(state: FourFourteenState): Card[] {
  if (state.phase !== 'playing' || state.currentPlayerIndex !== 0) return [];
  if (state.reaction?.kind === 'cha') {
    const pair = findSameRank(state.players[0].hand, state.reaction.targetRank, 2);
    return pair ?? [];
  }
  if (state.reaction?.kind === 'gou') {
    const single = findSameRank(state.players[0].hand, state.reaction.targetRank, 1);
    return single ?? [];
  }
  const combo = chooseHintCombo({
    ruleset: '414',
    playerIndex: 0,
    hands: state.players.map((player) => player.hand),
    previous: activeChallengeRecordFor(state, 0)?.combo,
    previousPlayerIndex: activeChallengeRecordFor(state, 0)?.playerIndex,
    deckCount: state.settings.deckCount,
    style: 'competitive',
    visibleCards: state.eventLog.flatMap((record) => record.cards),
    firstPlayMustContain: state.eventLog.length === 0 ? state.players[0].hand.find((card) => card.rank === '3' && card.suit === 'H') : undefined
  });
  return combo?.cards ?? [];
}

function aiStep(state: FourFourteenState): FourFourteenState {
  if (state.phase !== 'playing' || state.currentPlayerIndex === 0) return state;
  if (state.reaction) {
    const selected = chooseReactionCards(state, state.currentPlayerIndex);
    if (!selected) return applyPass(state, true);
    return applyReactionPlay(state, selected, state.reaction.kind);
  }
  const firstCard = state.eventLog.length === 0 ? state.players[state.currentPlayerIndex].hand.find((card) => card.rank === '3' && card.suit === 'H') : undefined;
  const combo = chooseAICombo({
    ruleset: '414',
    playerIndex: state.currentPlayerIndex,
    hands: state.players.map((player) => player.hand),
    previous: activeChallengeRecordFor(state, state.currentPlayerIndex)?.combo,
    previousPlayerIndex: activeChallengeRecordFor(state, state.currentPlayerIndex)?.playerIndex,
    deckCount: state.settings.deckCount,
    style: state.settings.aiStyle,
    visibleCards: state.eventLog.flatMap((record) => record.cards),
    firstPlayMustContain: firstCard
  });
  if (!combo) return applyPass(state, true);
  return applyPlay(state, combo.cards);
}

function applyPlay(state: FourFourteenState, selected: Card[]): FourFourteenState {
  const player = state.players[state.currentPlayerIndex];
  if (!containsAllCards(player.hand, selected)) return state;
  const combo = classify414(selected);
  if (!combo) return { ...state, message: '牌型不合法' };
  if (state.eventLog.length === 0 && !selected.some((card) => card.rank === '3' && card.suit === 'H')) {
    return { ...state, message: '首出必须带红桃3' };
  }
  const challenge = activeChallengeRecordFor(state, state.currentPlayerIndex);
  if (challenge?.combo && !legal414(player.hand, challenge.combo).some((candidate) => sameCards(candidate.cards, selected))) {
    return { ...state, message: '管不上当前牌' };
  }
  const players = updateHand(state.players, state.currentPlayerIndex, removeCards(player.hand, selected));
  const record = makeRecord(state, selected, combo, `${player.name}出${comboLabel(combo)}`);
  const nextState = afterRecord({ ...state, players }, record, true);
  if (players[state.currentPlayerIndex].hand.length === 0) return finish(nextState, state.currentPlayerIndex);
  if (combo.kind === 'single') {
    const reactionPlayers = reactionOrder(state.currentPlayerIndex, players.length).filter((index) => canChaHand(players[index].hand, combo.primaryRank));
    if (reactionPlayers.length > 0) {
      return {
        ...nextState,
        reaction: { kind: 'cha', targetRank: combo.primaryRank, sourcePlayerIndex: state.currentPlayerIndex, remainingPlayers: reactionPlayers },
        currentPlayerIndex: reactionPlayers[0],
        passCount: 0,
        lastPlay: record,
        message: `${record.label}，等待叉`
      };
    }
  }
  return {
    ...nextState,
    currentPlayerIndex: nextActive(players, state.currentPlayerIndex),
    passCount: 0,
    lastPlay: record,
    message: record.label
  };
}

function applyReactionPlay(state: FourFourteenState, selected: Card[], kind: 'cha' | 'gou'): FourFourteenState {
  const reaction = state.reaction;
  if (!reaction) return state;
  const player = state.players[state.currentPlayerIndex];
  const combo: Combo = {
    kind,
    cards: sortCards(selected),
    primaryRank: reaction.targetRank
  };
  const players = updateHand(state.players, state.currentPlayerIndex, removeCards(player.hand, selected));
  const record = makeRecord(state, selected, combo, `${player.name}${kind === 'cha' ? '叉' : '勾'}`);
  const next = afterRecord({ ...state, players }, record, true);
  if (players[state.currentPlayerIndex].hand.length === 0) return finish(next, state.currentPlayerIndex);
  if (kind === 'cha') {
    const remaining = reactionOrder(state.currentPlayerIndex, players.length)
      .filter((index) => index !== state.currentPlayerIndex)
      .filter((index) => canGouHand(players[index].hand, reaction.targetRank));
    if (remaining.length === 0) {
      return {
        ...next,
        reaction: undefined,
        currentPlayerIndex: state.currentPlayerIndex,
        passCount: 0,
        lastPlay: undefined,
        message: `${player.name}死叉，重新起手`
      };
    }
    return {
      ...next,
      reaction: { kind: 'gou', targetRank: reaction.targetRank, sourcePlayerIndex: state.currentPlayerIndex, remainingPlayers: remaining },
      currentPlayerIndex: remaining[0],
      passCount: 0,
      lastPlay: undefined,
      message: `${player.name}叉，等待勾`
    };
  }
  return {
    ...next,
    reaction: undefined,
    currentPlayerIndex: state.currentPlayerIndex,
    passCount: 0,
    lastPlay: undefined,
    message: `${player.name}勾，重新起手`
  };
}

function applyPass(state: FourFourteenState, silentReaction: boolean): FourFourteenState {
  if (state.reaction) {
    const [, ...rest] = state.reaction.remainingPlayers;
    if (rest.length === 0) {
      if (state.reaction.kind === 'cha') {
        const nextPlayer = nextActive(state.players, state.reaction.sourcePlayerIndex);
        return {
          ...state,
          reaction: undefined,
          currentPlayerIndex: nextPlayer,
          passCount: 0,
          message: `${state.players[nextPlayer].name}跟牌`
        };
      }
      const owner = state.reaction.sourcePlayerIndex;
      return {
        ...state,
        reaction: undefined,
        currentPlayerIndex: owner,
        lastPlay: undefined,
        passCount: 0,
        message: `${state.players[owner].name}重新起手`
      };
    }
    return {
      ...state,
      reaction: { ...state.reaction, remainingPlayers: rest },
      currentPlayerIndex: rest[0],
      message: silentReaction ? '思考中' : '你放弃反应'
    };
  }
  const challenge = activeChallengeRecordFor(state, state.currentPlayerIndex);
  if (!challenge) return state;
  const player = state.players[state.currentPlayerIndex];
  const record = makeRecord(state, [], undefined, `${player.name}过`, true);
  const passCount = state.passCount + 1;
  const tableRecords = [...state.tableRecords];
  tableRecords[state.currentPlayerIndex] = record;
  if (passCount >= state.players.filter((p) => !p.finished).length - 1) {
    const owner = challenge.playerIndex;
    return {
      ...state,
      tableRecords,
      eventLog: [...state.eventLog, record],
      currentPlayerIndex: owner,
      lastPlay: undefined,
      passCount: 0,
      message: `${state.players[owner].name}重新起手`
    };
  }
  return {
    ...state,
    tableRecords,
    eventLog: [...state.eventLog, record],
    currentPlayerIndex: nextActive(state.players, state.currentPlayerIndex),
    passCount,
    message: record.label
  };
}

function setOption(state: FourFourteenState, option: string, value: string | number): FourFourteenState {
  const settings = { ...state.settings };
  if (option === 'playerCount') settings.playerCount = Number(value) === 4 ? 4 : 3;
  if (option === 'deckCount') settings.deckCount = Math.max(1, Math.min(3, Number(value))) as 1 | 2 | 3;
  if (option === 'aiStyle') settings.aiStyle = value === 'competitive' ? 'competitive' : 'relaxed';
  return createFourFourteenState(settings);
}

function chooseReactionCards(state: FourFourteenState, playerIndex: number): Card[] | undefined {
  const reaction = state.reaction!;
  const hand = state.players[playerIndex].hand;
  const count = reaction.kind === 'cha' ? 2 : 1;
  const cards = findSameRank(hand, reaction.targetRank, count);
  if (!cards) return undefined;
  const pressure = Math.min(...state.players.map((player, index) => (index === playerIndex || player.hand.length === 0 ? 99 : player.hand.length)));
  const memory = new PublicCardMemory({
    deckCount: state.settings.deckCount,
    ownCards: hand,
    visibleCards: state.eventLog.flatMap((record) => record.cards)
  });
  if (state.settings.aiStyle === 'relaxed' && pressure > 3) return undefined;
  if (reaction.kind === 'cha' && reaction.targetRank === '2' && memory.opponentsCanGou('2') && pressure > 2) return undefined;
  const groupSize = hand.filter((card) => card.rank === reaction.targetRank).length;
  if (groupSize >= 3 && reaction.kind === 'gou' && pressure > 2) return undefined;
  return cards;
}

function canCha(cards: Card[], rank: Rank): boolean {
  return cards.length === 2 && cards.every((card) => card.rank === rank);
}

function canGou(cards: Card[], rank: Rank): boolean {
  return cards.length === 1 && cards[0].rank === rank;
}

function findSameRank(hand: Card[], rank: Rank, count: number): Card[] | undefined {
  const cards = sortCards(hand.filter((card) => card.rank === rank));
  return cards.length >= count ? cards.slice(0, count) : undefined;
}

function canChaHand(hand: Card[], rank: Rank): boolean {
  return hand.filter((card) => card.rank === rank).length >= 2;
}

function canGouHand(hand: Card[], rank: Rank): boolean {
  return hand.some((card) => card.rank === rank);
}

function afterRecord(state: FourFourteenState, record: TableRecord, visible: boolean): FourFourteenState {
  const tableRecords = [...state.tableRecords];
  tableRecords[record.playerIndex] = record;
  const effectMapping = comboEffect('414', record.combo);
  return {
    ...state,
    tableRecords,
    visibleRecord: visible ? record : state.visibleRecord,
    eventLog: [...state.eventLog, record],
    effect: effectMapping
      ? {
          id: state.effectSeq + 1,
          playerIndex: record.playerIndex,
          ...effectMapping
        }
      : undefined,
    effectSeq: state.effectSeq + 1
  };
}

function makeRecord(state: FourFourteenState, cards: Card[], combo: Combo | undefined, label: string, passed = false): TableRecord {
  return {
    id: tableRecordId(),
    playerIndex: state.currentPlayerIndex,
    cards: sortCards(cards),
    combo,
    label,
    passed
  };
}

function finish(state: FourFourteenState, winnerIndex: number): FourFourteenState {
  const scores = state.players.map((player, index) =>
    index === winnerIndex ? `${player.name} 先出完` : `${player.name} 剩 ${player.hand.length} 张`
  );
  return {
    ...state,
    phase: 'finished',
    currentPlayerIndex: winnerIndex,
    message: `${state.players[winnerIndex].name}获胜，所有人明牌`,
    scores,
    reaction: undefined,
    lastPlay: undefined,
    players: state.players.map((player) => ({ ...player, status: '明牌' }))
  };
}

function updateHand(players: PlayerState[], index: number, hand: Card[]): PlayerState[] {
  return players.map((player, playerIndex) =>
    playerIndex === index
      ? {
          ...player,
          hand: sortCards(hand),
          status: hand.length === 0 ? '出完' : '等待',
          finished: hand.length === 0
        }
      : player
  );
}

function reactionOrder(source: number, playerCount: number): number[] {
  return Array.from({ length: playerCount - 1 }, (_, offset) => (source + offset + 1) % playerCount);
}

function sameCards(lhs: Card[], rhs: Card[]): boolean {
  if (lhs.length !== rhs.length) return false;
  const ids = new Set(lhs.map((card) => card.id));
  return rhs.every((card) => ids.has(card.id));
}

export function activeChallengeRecordFor(state: FourFourteenState, playerIndex: number): TableRecord | undefined {
  if (!state.lastPlay || state.lastPlay.playerIndex === playerIndex) return undefined;
  return state.lastPlay;
}

function names(playerCount: 3 | 4): string[] {
  return playerCount === 3 ? ['你', 'AI 左', 'AI 右'] : ['你', 'AI 左', 'AI 上', 'AI 右'];
}
