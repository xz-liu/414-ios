export type EffectKind =
  | 'bomb'
  | 'mushroom'
  | 'rocket'
  | 'airplane'
  | 'straightTrail'
  | 'pairChain'
  | 'steelPlate'
  | 'straightFlush'
  | 'stamp';

export type EffectIntensity = 'c' | 'b' | 'a' | 's';

export interface TableEffect {
  id: number;
  kind: EffectKind;
  playerIndex: number;
  title: string;
  subtitle?: string;
  intensity: EffectIntensity;
}

export function effectDurationMs(intensity: EffectIntensity): number {
  switch (intensity) {
    case 's':
      return 1250;
    case 'a':
      return 1050;
    case 'b':
      return 850;
    case 'c':
      return 700;
  }
}
