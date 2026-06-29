import { Card, cardText, isRed, rankLabel, suitLabel } from '../core/cards';

interface CardViewProps {
  card: Card;
  selected?: boolean;
  mini?: boolean;
  marked?: boolean;
  onPointerDown?: (card: Card) => void;
  onPointerEnter?: (card: Card) => void;
}

export function CardView({ card, selected = false, mini = false, marked = false, onPointerDown, onPointerEnter }: CardViewProps) {
  const red = isRed(card);
  return (
    <button
      type="button"
      aria-label={cardText(card)}
      className={[
        'playing-card',
        red ? 'red' : 'black',
        selected ? 'selected' : '',
        mini ? 'mini' : '',
        marked ? 'marked' : ''
      ].join(' ')}
      onPointerDown={(event) => {
        event.currentTarget.setPointerCapture(event.pointerId);
        onPointerDown?.(card);
      }}
      onPointerEnter={() => onPointerEnter?.(card)}
    >
      <span className="rank">{rankLabel(card.rank)}</span>
      <span className="suit">{suitLabel(card.suit)}</span>
      {!mini && <span className="deck">#{card.deck + 1}</span>}
    </button>
  );
}
