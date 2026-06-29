import { useEffect, useMemo, useRef, useState } from 'react';
import { registerSW } from 'virtual:pwa-register';
import { Card, sortCards } from './core/cards';
import { effectDurationMs } from './core/effects';
import { isAudioEnabled, playEffectSound, playSound, setAudioEnabled, vibrateForEffect } from './core/audio';
import { gameModules, gameOrder } from './games/catalog';
import { ActionKey, GameKey, TableRecord, TableView } from './games/types';
import { CardView } from './ui/CardView';
import { EffectOverlay } from './ui/EffectOverlay';

const updateSW = registerSW({
  onNeedRefresh() {
    window.dispatchEvent(new Event('pwa-update-ready'));
  },
  onOfflineReady() {
    window.dispatchEvent(new Event('pwa-offline-ready'));
  }
});

export default function App() {
  const [gameKey, setGameKey] = useState<GameKey>(() => storedGameKey());
  const module = gameModules[gameKey];
  const [gameState, setGameState] = useState<unknown>(() => module.create());
  const view = module.view(gameState);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [dragMode, setDragMode] = useState<'select' | 'deselect' | undefined>();
  const [audioOn, setAudioOn] = useState(isAudioEnabled());
  const [updateReady, setUpdateReady] = useState(false);
  const [offlineReady, setOfflineReady] = useState(false);
  const [showInstallHint, setShowInstallHint] = useState(false);
  const lastEffectId = useRef<number | undefined>(undefined);

  const humanHand = view.players[0]?.hand ?? [];
  const selectedCards = useMemo(() => humanHand.filter((card) => selectedIds.has(card.id)), [humanHand, selectedIds]);
  const legalActions = module.legalActions(gameState, selectedCards);

  useEffect(() => {
    localStorage.setItem('pwa-game', gameKey);
  }, [gameKey]);

  useEffect(() => {
    const onUpdate = () => setUpdateReady(true);
    const onOffline = () => setOfflineReady(true);
    window.addEventListener('pwa-update-ready', onUpdate);
    window.addEventListener('pwa-offline-ready', onOffline);
    return () => {
      window.removeEventListener('pwa-update-ready', onUpdate);
      window.removeEventListener('pwa-offline-ready', onOffline);
    };
  }, []);

  useEffect(() => {
    const standalone = window.matchMedia('(display-mode: standalone)').matches || Boolean((navigator as Navigator & { standalone?: boolean }).standalone);
    const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    setShowInstallHint(isIOS && !standalone);
  }, []);

  useEffect(() => {
    setAudioEnabled(audioOn);
  }, [audioOn]);

  useEffect(() => {
    if (!view.effect || lastEffectId.current === view.effect.id) return;
    lastEffectId.current = view.effect.id;
    playEffectSound(view.effect.kind);
    vibrateForEffect(view.effect.kind);
  }, [view.effect]);

  useEffect(() => {
    if (view.phase === 'idle' || view.phase === 'finished' || module.isHumanTurn(gameState)) return;
    const delay = view.effect ? effectDurationMs(view.effect.intensity) + 150 : view.phase === 'bidding' ? 520 : 720;
    const timer = window.setTimeout(() => {
      setGameState((current: unknown) => module.aiStep(current));
      setSelectedIds(new Set());
    }, delay);
    return () => window.clearTimeout(timer);
  }, [gameState, module, view.phase, view.currentPlayerIndex, view.effect]);

  function changeGame(next: GameKey) {
    setGameKey(next);
    setGameState(gameModules[next].create());
    setSelectedIds(new Set());
  }

  function applyAction(action: ActionKey) {
    if (action === 'hint') {
      const cards = module.hint(gameState);
      setSelectedIds(new Set(cards.map((card) => card.id)));
      playSound('tap');
      return;
    }
    if (action === 'clear') {
      setSelectedIds(new Set());
      playSound('tap');
      return;
    }
    if (action === 'deal') {
      setGameState((current: unknown) => module.deal(current));
      setSelectedIds(new Set());
      playSound('deal');
      return;
    }
    setGameState((current: unknown) => module.apply(current, action, selectedCards));
    setSelectedIds(new Set());
    playSound(action === 'pass' || action === 'bid0' ? 'pass' : 'play');
  }

  function setOption(option: string, value: string | number) {
    if (!module.setOption) return;
    setGameState((current: unknown) => module.setOption!(current, option, value));
    setSelectedIds(new Set());
  }

  function pointerDown(card: Card) {
    const mode = selectedIds.has(card.id) ? 'deselect' : 'select';
    setDragMode(mode);
    setSelectedIds((current) => applySelection(current, card.id, mode));
  }

  function pointerEnter(card: Card) {
    if (!dragMode) return;
    setSelectedIds((current) => applySelection(current, card.id, dragMode));
  }

  return (
    <main className="app-shell" onPointerUp={() => setDragMode(undefined)} onPointerCancel={() => setDragMode(undefined)}>
      <header className="topbar">
        <div className="brand">
          <strong>414 Poker</strong>
          <span>{view.message}</span>
        </div>
        <nav className="game-tabs" aria-label="选择玩法">
          {gameOrder.map((key) => (
            <button key={key} type="button" className={key === gameKey ? 'active' : ''} onClick={() => changeGame(key)}>
              {gameModules[key].title}
            </button>
          ))}
        </nav>
        <div className="top-actions">
          {gameKey === '414' && <FourFourteenSettings view={view} setOption={setOption} />}
          <button type="button" className="icon-action" onClick={() => setAudioOn((value) => !value)} aria-label="音效">
            {audioOn ? '音' : '静'}
          </button>
          <button type="button" className="deal-action" onClick={() => applyAction('deal')}>
            {view.phase === 'idle' ? '发牌' : '重发'}
          </button>
        </div>
      </header>

      <section className={`table table-${view.players.length}`}>
        <div className="table-felt" />
        {view.players.map((player) => (
          <PlayerCluster key={player.id} view={view} playerIndex={player.id} />
        ))}
        {view.tableRecords.map((record, index) => (
          <PlaySlot key={index} view={view} playerIndex={index} record={record} />
        ))}
        <div className="center-message">
          <strong>{view.visibleRecord?.label ?? view.title}</strong>
          <span>{view.subtitle}</span>
          {view.scores && view.scores.length > 0 && (
            <div className="scores">
              {view.scores.map((score) => (
                <span key={score}>{score}</span>
              ))}
            </div>
          )}
        </div>
        <EffectOverlay effect={view.effect} seatCount={view.players.length} />
      </section>

      <footer className="hand-zone">
        <div className="hand-meta">
          <span>你的手牌 {humanHand.length}张</span>
          <span>{view.settingsSummary}</span>
        </div>
        <div className="hand-scroll">
          <div className="hand-grid">
            {sortCards(humanHand).map((card) => (
              <CardView
                key={card.id}
                card={card}
                selected={selectedIds.has(card.id)}
                onPointerDown={pointerDown}
                onPointerEnter={pointerEnter}
              />
            ))}
          </div>
        </div>
        <ActionBar actions={legalActions} applyAction={applyAction} phase={view.phase} />
      </footer>

      {view.phase === 'finished' && <RevealStrip view={view} />}

      <div className="toast-stack">
        {showInstallHint && <div className="toast">iPhone 安装：Safari 分享按钮 → 添加到主屏幕。首次加载后可离线运行。</div>}
        {offlineReady && <div className="toast">离线缓存已准备好。</div>}
        {updateReady && (
          <button type="button" className="toast update" onClick={() => updateSW(true)}>
            有新版本，点此刷新
          </button>
        )}
      </div>
    </main>
  );
}

function FourFourteenSettings({ view, setOption }: { view: TableView; setOption: (option: string, value: string | number) => void }) {
  const summary = view.settingsSummary ?? '';
  const playerCount = summary.includes('4人') ? 4 : 3;
  const deckCount = Number(summary.match(/(\d)副/)?.[1] ?? 1);
  const competitive = summary.includes('竞技');
  return (
    <div className="inline-settings">
      <button type="button" className={playerCount === 3 ? 'active' : ''} onClick={() => setOption('playerCount', 3)}>
        3人
      </button>
      <button type="button" className={playerCount === 4 ? 'active' : ''} onClick={() => setOption('playerCount', 4)}>
        4人
      </button>
      <button type="button" onClick={() => setOption('deckCount', Math.max(1, deckCount - 1))}>
        -
      </button>
      <span>{deckCount}副</span>
      <button type="button" onClick={() => setOption('deckCount', Math.min(3, deckCount + 1))}>
        +
      </button>
      <button type="button" className={!competitive ? 'active' : ''} onClick={() => setOption('aiStyle', 'relaxed')}>
        休闲
      </button>
      <button type="button" className={competitive ? 'active' : ''} onClick={() => setOption('aiStyle', 'competitive')}>
        竞技
      </button>
    </div>
  );
}

function ActionBar({ actions, applyAction, phase }: { actions: ActionKey[]; applyAction: (action: ActionKey) => void; phase: string }) {
  const labels: Record<ActionKey, string> = {
    deal: phase === 'idle' ? '发牌' : '重发',
    play: '出牌',
    pass: '过',
    hint: '提示',
    clear: '全取消',
    cha: '叉',
    gou: '勾',
    bid0: '不叫',
    bid1: '1分',
    bid2: '2分',
    bid3: '3分'
  };
  const order: ActionKey[] = ['hint', 'clear', 'pass', 'cha', 'gou', 'play', 'bid0', 'bid1', 'bid2', 'bid3'];
  return (
    <div className="action-bar">
      {order.map((action) => (
        <button
          key={action}
          type="button"
          disabled={!actions.includes(action)}
          className={['action-button', actions.includes(action) ? 'enabled' : '', action === 'play' || action === 'cha' || action === 'gou' ? 'primary' : ''].join(' ')}
          onClick={() => applyAction(action)}
        >
          {labels[action]}
        </button>
      ))}
    </div>
  );
}

function PlayerCluster({ view, playerIndex }: { view: TableView; playerIndex: number }) {
  const player = view.players[playerIndex];
  return (
    <div className={`player-cluster ${seatClass(playerIndex, view.players.length)} ${view.currentPlayerIndex === playerIndex ? 'current' : ''}`}>
      <strong>{player.name}</strong>
      <span>
        {player.hand.length}张 {player.role ?? player.team ?? ''}
      </span>
      <small>{view.currentPlayerIndex === playerIndex ? '行动中' : player.status ?? '等待'}</small>
    </div>
  );
}

function PlaySlot({ view, playerIndex, record }: { view: TableView; playerIndex: number; record?: TableRecord }) {
  return (
    <div className={`play-slot ${seatClass(playerIndex, view.players.length)}`}>
      {record ? (
        <>
          <span className={record.passed ? 'pass-label' : 'slot-label'}>{record.label}</span>
          <div className="slot-cards">
            {record.cards.slice(0, 12).map((card) => (
              <CardView key={card.id} card={card} mini />
            ))}
            {record.cards.length > 12 && <span className="more-cards">+{record.cards.length - 12}</span>}
          </div>
        </>
      ) : (
        <span className="slot-placeholder">{view.players[playerIndex]?.name}</span>
      )}
    </div>
  );
}

function RevealStrip({ view }: { view: TableView }) {
  return (
    <aside className="reveal-strip">
      {view.players.slice(1).map((player) => (
        <div key={player.id} className="reveal-player">
          <span>{player.name}</span>
          <div>
            {sortCards(player.hand).map((card) => (
              <CardView key={card.id} card={card} mini />
            ))}
          </div>
        </div>
      ))}
    </aside>
  );
}

function applySelection(current: Set<string>, cardId: string, mode: 'select' | 'deselect'): Set<string> {
  const next = new Set(current);
  if (mode === 'select') next.add(cardId);
  else next.delete(cardId);
  return next;
}

function seatClass(index: number, seatCount: number): string {
  if (index === 0) return 'seat-bottom';
  if (seatCount === 3) return index === 1 ? 'seat-left' : 'seat-right';
  if (index === 1) return 'seat-left';
  if (index === 2) return 'seat-top';
  return 'seat-right';
}

function storedGameKey(): GameKey {
  const value = localStorage.getItem('pwa-game') as GameKey | null;
  return value && gameOrder.includes(value) ? value : '414';
}
