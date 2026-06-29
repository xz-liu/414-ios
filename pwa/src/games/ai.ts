import { Card, Rank, groupByRank, rankValue, removeCards, sortCards } from '../core/cards';
import { Combo, Ruleset, comboSortScore, legalCombinations } from '../core/rules';
import { PublicCardMemory } from '../core/publicMemory';

export interface AIContext {
  ruleset: Ruleset;
  playerIndex: number;
  hands: Card[][];
  previous?: Combo;
  previousPlayerIndex?: number;
  landlordIndex?: number;
  teamOf?: (playerIndex: number) => string;
  deckCount?: number;
  levelRank?: Rank;
  style?: 'relaxed' | 'competitive';
  visibleCards?: Card[];
  firstPlayMustContain?: Card;
}

export function chooseAICombo(context: AIContext): Combo | undefined {
  const hand = context.hands[context.playerIndex];
  let legal = legalCombinations(context.ruleset, hand, context.previous, context.levelRank);
  if (context.firstPlayMustContain) {
    legal = legal.filter((combo) => combo.cards.some((card) => card.id === context.firstPlayMustContain!.id));
  }
  if (legal.length === 0) return undefined;

  const finishing = legal.filter((combo) => combo.cards.length === hand.length).sort((a, b) => comboSortScore(a, context.levelRank) - comboSortScore(b, context.levelRank));
  if (finishing.length > 0) return finishing[0];

  const scored = legal.map((combo) => ({
    combo,
    score: scoreCombo(combo, context)
  }));
  scored.sort((a, b) => b.score - a.score || comboSortScore(a.combo, context.levelRank) - comboSortScore(b.combo, context.levelRank));
  const best = scored[0];
  if (context.previous && passScore(context) >= best.score) return undefined;
  return best.combo;
}

export function chooseHintCombo(context: AIContext): Combo | undefined {
  const hand = context.hands[context.playerIndex];
  let legal = legalCombinations(context.ruleset, hand, context.previous, context.levelRank);
  if (context.firstPlayMustContain) {
    legal = legal.filter((combo) => combo.cards.some((card) => card.id === context.firstPlayMustContain!.id));
  }
  const finishing = legal.find((combo) => combo.cards.length === hand.length);
  if (finishing) return finishing;
  return chooseAICombo({ ...context, style: 'competitive' }) ?? legal[0];
}

export function estimateTurns(cards: Card[], ruleset: Ruleset, levelRank?: Rank): number {
  if (cards.length === 0) return 0;
  if (legalCombinations(ruleset, cards, undefined, levelRank).some((combo) => combo.cards.length === cards.length)) return 1;
  let remaining = sortCards(cards, levelRank);
  let turns = 0;
  while (remaining.length > 0 && turns < 40) {
    const combos = legalCombinations(ruleset, remaining, undefined, levelRank)
      .filter((combo) => combo.cards.length <= remaining.length)
      .sort((a, b) => planningScore(b, ruleset, levelRank) - planningScore(a, ruleset, levelRank));
    const combo = combos[0];
    if (!combo) {
      turns += remaining.length;
      break;
    }
    remaining = removeCards(remaining, combo.cards);
    turns += 1;
  }
  return turns;
}

function scoreCombo(combo: Combo, context: AIContext): number {
  const hand = context.hands[context.playerIndex];
  const remaining = removeCards(hand, combo.cards);
  const beforeTurns = estimateTurns(hand, context.ruleset, context.levelRank);
  const afterTurns = estimateTurns(remaining, context.ruleset, context.levelRank);
  const pressure = tablePressure(context);
  let score = (beforeTurns - afterTurns) * 900 + combo.cards.length * 28 - rankValue(combo.primaryRank, context.levelRank) * 7;

  if (!context.previous) {
    score += leadShapeBonus(combo, context);
  } else {
    score += 140 + pressure * 22;
  }

  score -= resourceCost(combo, context);
  score -= structureBreakCost(combo, hand, context);

  if (context.ruleset === '414') {
    score -= publicMemoryRisk(combo, context);
  }

  if (context.ruleset === 'doudizhu') {
    score += douDizhuTeamAdjustment(combo, context);
  }

  if (context.ruleset === 'guandan') {
    score += guanDanTeamAdjustment(combo, context);
  }

  if (context.style === 'relaxed' && context.previous && pressure < 5) {
    score -= 180;
  }
  return score;
}

function passScore(context: AIContext): number {
  if (!context.previous) return -100000;
  const pressure = tablePressure(context);
  let score = 60 - pressure * 85;
  if (context.style === 'relaxed' && pressure < 5) score += 230;
  if (context.ruleset === 'doudizhu' && context.landlordIndex != null && context.previousPlayerIndex !== context.landlordIndex) {
    const myTeam = context.playerIndex === context.landlordIndex ? 'landlord' : 'farmer';
    const prevTeam = context.previousPlayerIndex === context.landlordIndex ? 'landlord' : 'farmer';
    if (myTeam === 'farmer' && prevTeam === 'farmer') score += 480;
  }
  if (context.ruleset === 'guandan' && context.teamOf && context.previousPlayerIndex != null) {
    if (context.teamOf(context.playerIndex) === context.teamOf(context.previousPlayerIndex)) score += 420;
  }
  return score;
}

function tablePressure(context: AIContext): number {
  const opponents = context.hands
    .map((hand, index) => ({ index, count: hand.length }))
    .filter((entry) => entry.index !== context.playerIndex && entry.count > 0);
  const min = Math.min(...opponents.map((entry) => entry.count));
  const progress = Math.max(0, 20 - context.hands[context.playerIndex].length) / 3;
  if (min <= 1) return 10 + progress;
  if (min <= 2) return 8 + progress;
  if (min <= 4) return 5 + progress;
  return progress;
}

function leadShapeBonus(combo: Combo, context: AIContext): number {
  const opponentMin = Math.min(...context.hands.map((hand, index) => (index === context.playerIndex || hand.length === 0 ? 99 : hand.length)));
  let bonus = 0;
  switch (combo.kind) {
    case 'singleRun':
    case 'singleStraight':
    case 'pairRun':
    case 'pairStraight':
      bonus += 480 + combo.cards.length * 22;
      break;
    case 'airplaneWithSingles':
    case 'airplaneWithPairs':
    case 'airplaneWithWings':
      bonus += 560 + combo.cards.length * 24;
      break;
    case 'airplane':
      bonus += combo.cards.length === context.hands[context.playerIndex].length ? 800 : -250;
      break;
    case 'trioWithPair':
    case 'trioWithSingle':
    case 'trioWithTwo':
      bonus += context.ruleset === '414' ? -180 : 320;
      break;
    case 'single':
      bonus += opponentMin <= 1 ? -550 : 20;
      break;
    case 'pair':
      bonus += opponentMin <= 1 ? 260 : 80;
      break;
    default:
      break;
  }
  if (opponentMin <= 2 && combo.cards.length >= 3) bonus += 400;
  return bonus;
}

function resourceCost(combo: Combo, context: AIContext): number {
  let cost = 0;
  const pressure = tablePressure(context);
  for (const card of combo.cards) {
    if (card.rank === '2') cost += 95;
    if (card.rank === 'SJ') cost += 190;
    if (card.rank === 'BJ') cost += 240;
  }
  switch (combo.kind) {
    case 'rocket414':
    case 'rocket':
    case 'jokerBomb':
      cost += 1150;
      break;
    case 'doubleJoker':
      cost += 880;
      break;
    case 'sameRankBomb':
    case 'bomb':
      cost += 620 + (combo.cards.length - 3) * 120;
      break;
    case 'straightFlush':
      cost += 760;
      break;
    default:
      break;
  }
  if (context.ruleset === '414') {
    cost = Math.round(cost * fourFourteenResourceCoefficient(context));
  }
  if (context.style === 'relaxed' && pressure < 6) cost = Math.round(cost * 1.25);
  return Math.max(0, cost - pressure * 85);
}

function fourFourteenResourceCoefficient(context: AIContext): number {
  const deckCount = context.deckCount ?? 1;
  const hand = context.hands[context.playerIndex];
  const groups = groupByRank(hand);
  const bombGroups = [...groups.values()].filter((cards) => cards.length >= 3).length;
  const hasRocket414 = (groups.get('4')?.length ?? 0) >= 2 && (groups.get('A')?.length ?? 0) >= 1;
  const hasDoubleJoker = (groups.get('SJ')?.length ?? 0) >= 1 && (groups.get('BJ')?.length ?? 0) >= 1;
  const controlLoad = bombGroups + (hasRocket414 ? 1.5 : 0) + (hasDoubleJoker ? 1 : 0);
  const expected = Math.max(1, deckCount * 1.7);
  return Math.max(0.45, Math.min(1.2, expected / Math.max(expected, controlLoad)));
}

function structureBreakCost(combo: Combo, hand: Card[], context: AIContext): number {
  if (combo.cards.length === hand.length) return 0;
  const beforeGroups = groupByRank(hand);
  const afterGroups = groupByRank(removeCards(hand, combo.cards));
  let cost = 0;
  for (const [rank, cards] of beforeGroups) {
    if (cards.length >= 3 && (afterGroups.get(rank)?.length ?? 0) < 3) {
      cost += context.ruleset === '414' ? 420 : 180;
    }
    if (cards.length >= 4 && (afterGroups.get(rank)?.length ?? 0) < 4) {
      cost += 480;
    }
  }
  return cost;
}

function publicMemoryRisk(combo: Combo, context: AIContext): number {
  if (!context.visibleCards || context.deckCount == null) return 0;
  const memory = new PublicCardMemory({
    deckCount: context.deckCount,
    ownCards: context.hands[context.playerIndex],
    visibleCards: context.visibleCards
  });
  if (combo.kind === 'single' && !memory.opponentsCanCha(combo.primaryRank)) return -80;
  if (combo.kind === 'doubleJoker' && !memory.opponentsCanHaveRocket414()) return -160;
  if (combo.kind === 'sameRankBomb') {
    const higherRisk = ['3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A', '2'].filter(
      (rank) => rankValue(rank as Rank) > rankValue(combo.primaryRank) && memory.opponentsCanHaveSameRankBomb(rank as Rank, combo.sameRankCount ?? combo.cards.length)
    ).length;
    return higherRisk * 55;
  }
  return 0;
}

function douDizhuTeamAdjustment(combo: Combo, context: AIContext): number {
  if (context.landlordIndex == null || context.previousPlayerIndex == null || !context.previous) return 0;
  const isFarmer = context.playerIndex !== context.landlordIndex;
  const previousIsFarmer = context.previousPlayerIndex !== context.landlordIndex;
  const landlordShort = context.hands[context.landlordIndex]?.length <= 3;
  if (isFarmer && previousIsFarmer && !landlordShort) return combo.cards.length === context.hands[context.playerIndex].length ? 900 : -900;
  if (isFarmer && context.previousPlayerIndex === context.landlordIndex) return landlordShort ? 550 : 260;
  return 0;
}

function guanDanTeamAdjustment(combo: Combo, context: AIContext): number {
  if (!context.teamOf || context.previousPlayerIndex == null || !context.previous) return 0;
  if (context.teamOf(context.playerIndex) === context.teamOf(context.previousPlayerIndex)) {
    return combo.cards.length === context.hands[context.playerIndex].length ? 900 : -820;
  }
  return 220;
}

function planningScore(combo: Combo, ruleset: Ruleset, levelRank?: Rank): number {
  let score = combo.cards.length * 90 - rankValue(combo.primaryRank, levelRank) * 4;
  switch (combo.kind) {
    case 'singleRun':
    case 'singleStraight':
    case 'pairRun':
    case 'pairStraight':
      score += 500;
      break;
    case 'airplaneWithSingles':
    case 'airplaneWithPairs':
    case 'airplaneWithWings':
      score += 620;
      break;
    case 'airplane':
      score += 320;
      break;
    case 'trioWithSingle':
    case 'trioWithPair':
    case 'trioWithTwo':
      score += ruleset === '414' ? -100 : 260;
      break;
    case 'sameRankBomb':
    case 'bomb':
    case 'doubleJoker':
    case 'rocket414':
    case 'rocket':
    case 'jokerBomb':
      score -= ruleset === '414' ? 180 : 320;
      break;
    default:
      break;
  }
  return score;
}
