import { EffectKind } from './effects';

const files = {
  tap: '/audio/tap.wav',
  deal: '/audio/shuffle.wav',
  play: '/audio/playcard.wav',
  pass: '/audio/pass.wav',
  bomb: '/audio/bomb_bang.wav',
  rocket: '/audio/rocket_launch.wav',
  reaction: '/audio/reaction.wav'
};

let enabled = true;

export function setAudioEnabled(value: boolean): void {
  enabled = value;
}

export function isAudioEnabled(): boolean {
  return enabled;
}

export function playSound(name: keyof typeof files): void {
  if (!enabled) return;
  const audio = new Audio(files[name]);
  audio.volume = name === 'bomb' || name === 'rocket' ? 0.55 : 0.35;
  void audio.play().catch(() => {
    // iOS requires a user gesture before audio can start.
  });
}

export function playEffectSound(kind?: EffectKind): void {
  switch (kind) {
    case 'bomb':
    case 'mushroom':
      playSound('bomb');
      break;
    case 'rocket':
      playSound('rocket');
      break;
    case 'stamp':
      playSound('reaction');
      break;
    default:
      playSound('play');
  }
}

export function vibrateForEffect(kind?: EffectKind): void {
  if (!('vibrate' in navigator)) return;
  switch (kind) {
    case 'mushroom':
    case 'rocket':
      navigator.vibrate([40, 30, 80]);
      break;
    case 'bomb':
      navigator.vibrate([35, 25, 45]);
      break;
    case 'stamp':
      navigator.vibrate(25);
      break;
    default:
      navigator.vibrate(10);
  }
}
