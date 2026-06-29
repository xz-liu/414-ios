import { TableEffect } from '../core/effects';

interface EffectOverlayProps {
  effect?: TableEffect;
  seatCount: number;
}

export function EffectOverlay({ effect, seatCount }: EffectOverlayProps) {
  if (!effect) return null;
  const seat = seatClass(effect.playerIndex, seatCount);
  return (
    <div key={effect.id} className={`effect-overlay ${seat} ${effect.kind} intensity-${effect.intensity}`} aria-hidden="true">
      <div className="effect-burst">
        <span className="effect-title">{effect.title}</span>
        {effect.subtitle && <span className="effect-subtitle">{effect.subtitle}</span>}
      </div>
      <div className="effect-particles">
        <i />
        <i />
        <i />
        <i />
        <i />
      </div>
    </div>
  );
}

function seatClass(index: number, seatCount: number): string {
  if (index === 0) return 'seat-bottom';
  if (seatCount === 3) return index === 1 ? 'seat-left' : 'seat-right';
  if (index === 1) return 'seat-left';
  if (index === 2) return 'seat-top';
  return 'seat-right';
}
