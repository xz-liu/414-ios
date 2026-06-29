import { Card, Rank, countRank } from './cards';

export interface PublicCardMemoryInput {
  deckCount: number;
  ownCards: Card[];
  visibleCards: Card[];
}

export class PublicCardMemory {
  private readonly deckCount: number;
  private readonly ownCards: Card[];
  private readonly visibleCards: Card[];

  constructor(input: PublicCardMemoryInput) {
    this.deckCount = input.deckCount;
    this.ownCards = input.ownCards;
    this.visibleCards = input.visibleCards;
  }

  opponentAvailableCount(rank: Rank): number {
    return Math.max(0, this.totalCount(rank) - countRank(this.ownCards, rank) - countRank(this.visibleCards, rank));
  }

  rankExhausted(rank: Rank): boolean {
    return this.opponentAvailableCount(rank) === 0;
  }

  opponentsCanHaveRocket414(): boolean {
    return this.opponentAvailableCount('4') >= 2 && this.opponentAvailableCount('A') >= 1;
  }

  opponentsCanHaveDoubleJoker(): boolean {
    return this.opponentAvailableCount('SJ') >= 1 && this.opponentAvailableCount('BJ') >= 1;
  }

  opponentsCanHaveSameRankBomb(rank: Rank, count: number): boolean {
    if (rank === 'SJ' || rank === 'BJ') return false;
    return this.opponentAvailableCount(rank) >= count;
  }

  opponentsCanCha(rank: Rank): boolean {
    if (rank === 'SJ' || rank === 'BJ') return false;
    return this.opponentAvailableCount(rank) >= 2;
  }

  opponentsCanGou(rank: Rank): boolean {
    return this.opponentAvailableCount(rank) >= 1;
  }

  private totalCount(rank: Rank): number {
    return rank === 'SJ' || rank === 'BJ' ? this.deckCount : this.deckCount * 4;
  }
}
