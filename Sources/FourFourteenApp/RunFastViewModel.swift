import Foundation
import SwiftUI

@MainActor
final class RunFastViewModel: ObservableObject {
    @Published var selectedCards: Set<Card> = []
    @Published var notice: String = ""
    @Published var phase: GamePhase = .waiting
    @Published var tableEffect: CardGameEffectDescriptor?
    @Published var visibleHandCounts: [Int] = [0, 0, 0]
    @Published var soundEnabled = true {
        didSet { audio.effectsEnabled = soundEnabled }
    }
    @Published var musicEnabled = false {
        didSet { audio.setMusicEnabled(musicEnabled) }
    }

    private(set) var engine = RunFastGameEngine()
    private var isAdvancingAI = false
    private let audio = AudioController()

    var state: RunFastState {
        engine.state
    }

    var humanHand: [Card] {
        switch phase {
        case .waiting:
            return []
        case .dealing:
            return Array(state.hands[0].prefix(visibleCardCount(for: 0)))
        case .playing:
            return state.hands[0]
        }
    }

    var isHumanTurn: Bool {
        phase == .playing && state.currentPlayerIndex == 0 && !state.isGameOver
    }

    var isWaiting: Bool {
        phase == .waiting
    }

    var isDealing: Bool {
        phase == .dealing
    }

    var canHint: Bool {
        phase == .playing && isHumanTurn
    }

    var canPlay: Bool {
        phase == .playing && isHumanTurn && !selectedCards.isEmpty
    }

    var canPassPlay: Bool {
        guard phase == .playing, isHumanTurn else { return false }
        return state.lastPlay != nil && state.lastPlay?.playerIndex != 0
    }

    var promptText: String {
        switch phase {
        case .waiting:
            return "点发牌开始"
        case .dealing:
            return "正在发牌..."
        case .playing:
            break
        }

        if state.isGameOver {
            return "\(state.players[state.winnerIndex ?? 0].name)跑完"
        }
        if state.currentPlayerIndex == 0 {
            return state.lastPlay == nil || state.lastPlay?.playerIndex == 0 ? "你出牌" : "你跟牌或过"
        }
        return "\(state.players[state.currentPlayerIndex].name)思考中"
    }

    func dealNewGame() {
        guard phase != .dealing else { return }
        selectedCards.removeAll()
        notice = ""
        tableEffect = nil
        engine = RunFastGameEngine()
        visibleHandCounts = [0, 0, 0]
        phase = .dealing
        audio.play(.shuffle)
        objectWillChange.send()
        animateDeal()
    }

    func toggle(_ card: Card) {
        guard isHumanTurn else { return }
        audio.play(.tap)
        if selectedCards.contains(card) {
            selectedCards.remove(card)
        } else {
            selectedCards.insert(card)
        }
    }

    func select(_ cards: [Card]) {
        guard isHumanTurn else { return }
        let newCards = cards.filter { !selectedCards.contains($0) }
        guard !newCards.isEmpty else { return }
        selectedCards.formUnion(newCards)
    }

    func flipSelection(_ cards: [Card]) {
        guard isHumanTurn else { return }
        guard !cards.isEmpty else { return }
        for card in cards {
            if selectedCards.contains(card) {
                selectedCards.remove(card)
            } else {
                selectedCards.insert(card)
            }
        }
    }

    func clearSelection() {
        guard !selectedCards.isEmpty else { return }
        selectedCards.removeAll()
        audio.play(.tap)
    }

    func playSelected() {
        apply(.play(Array(selectedCards)))
    }

    func passPlay() {
        apply(.pass)
    }

    func hint() {
        guard let action = RunFastHintEngine.bestAction(state: state, for: 0) else {
            notice = "当前没有可提示的牌"
            audio.play(.error)
            return
        }
        selectedCards = Set(action.cards)
        notice = "已选中推荐牌"
        audio.play(.tap)
    }

    func toggleSound() {
        soundEnabled.toggle()
        if soundEnabled {
            audio.play(.tap)
        }
    }

    func toggleMusic() {
        musicEnabled.toggle()
    }

    func visibleCardCount(for playerIndex: Int) -> Int {
        switch phase {
        case .waiting:
            return 0
        case .dealing:
            return visibleHandCounts.indices.contains(playerIndex) ? visibleHandCounts[playerIndex] : 0
        case .playing:
            return state.hands.indices.contains(playerIndex) ? state.hands[playerIndex].count : 0
        }
    }

    func tableRecord(for playerIndex: Int) -> RunFastPlayRecord? {
        state.tableRecords.indices.contains(playerIndex) ? state.tableRecords[playerIndex] : nil
    }

    func statusText(for playerIndex: Int) -> String {
        switch phase {
        case .waiting:
            return "待发牌"
        case .dealing:
            return "发牌中"
        case .playing:
            break
        }
        if state.winnerIndex == playerIndex {
            return "赢家"
        }
        if state.currentPlayerIndex == playerIndex {
            return state.lastPlay == nil || state.lastPlay?.playerIndex == playerIndex ? "起手" : "跟牌"
        }
        return "等待"
    }
}

private extension RunFastViewModel {
    func animateDeal() {
        notice = "正在发牌..."
        let targetCounts = engine.state.hands.map(\.count)
        let delay: UInt64 = 42_000_000

        Task { @MainActor in
            var remaining = targetCounts.reduce(0, +)
            while remaining > 0 {
                var changed = false
                withAnimation(.easeOut(duration: 0.10)) {
                    for playerIndex in targetCounts.indices where visibleHandCounts[playerIndex] < targetCounts[playerIndex] {
                        visibleHandCounts[playerIndex] += 1
                        remaining -= 1
                        changed = true
                    }
                }
                if changed {
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            notice = "黑桃3先出"
            audio.play(.draw)
            try? await Task.sleep(nanoseconds: 720_000_000)
            phase = .playing
            notice = ""
            objectWillChange.send()
            advanceAIIfNeeded()
        }
    }

    func apply(_ action: RunFastAction) {
        guard phase == .playing else { return }
        do {
            try engine.apply(action)
            selectedCards.removeAll()
            notice = ""
            let effect = showEffectFromLatestEvent()
            playSoundForLatestEvent(effect: effect)
            objectWillChange.send()
            advanceAIIfNeeded()
        } catch {
            notice = message(for: error)
            audio.play(.error)
        }
    }

    func advanceAIIfNeeded() {
        guard phase == .playing, !isAdvancingAI else { return }
        isAdvancingAI = true
        Task { @MainActor in
            defer { isAdvancingAI = false }
            while !engine.state.isGameOver,
                  !engine.state.players[engine.state.currentPlayerIndex].isHuman {
                let playerIndex = engine.state.currentPlayerIndex
                notice = "\(engine.state.players[playerIndex].name)思考中..."
                try? await Task.sleep(nanoseconds: 820_000_000)

                let snapshot = engine.state
                let action = await Task.detached(priority: .userInitiated) {
                    RunFastAIPlayer().chooseAction(state: snapshot, for: playerIndex)
                }.value

                guard phase == .playing, engine.state == snapshot else { continue }
                do {
                    try engine.apply(action)
                    notice = ""
                    let effect = showEffectFromLatestEvent()
                    playSoundForLatestEvent(effect: effect)
                    objectWillChange.send()
                    try? await Task.sleep(nanoseconds: pauseAfterLatestEvent(effect: effect))
                } catch {
                    notice = message(for: error)
                    audio.play(.error)
                    break
                }
            }
        }
    }

    func playSoundForLatestEvent(effect: CardGameEffectDescriptor? = nil) {
        guard let record = engine.state.eventLog.last else { return }
        switch record.kind {
        case .play:
            audio.playCard(effect: effect ?? CardGameEffectMapper.effect(for: record))
        case .pass:
            audio.play(.pass)
        case .system:
            audio.play(.tap)
        }
    }

    @discardableResult
    func showEffectFromLatestEvent() -> CardGameEffectDescriptor? {
        guard let record = engine.state.eventLog.last,
              let effect = CardGameEffectMapper.effect(for: record)
        else { return nil }
        tableEffect = effect
        let effectID = effect.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: effect.intensity.durationNanoseconds)
            if tableEffect?.id == effectID {
                tableEffect = nil
            }
        }
        return effect
    }

    func pauseAfterLatestEvent(effect: CardGameEffectDescriptor?) -> UInt64 {
        let base: UInt64 = 820_000_000
        guard let effect else { return base }
        let extra: UInt64 = effect.intensity.isMajor ? 200_000_000 : 120_000_000
        return max(base, effect.intensity.durationNanoseconds + extra)
    }

    func message(for error: Error) -> String {
        guard let error = error as? RunFastError else {
            return "操作失败"
        }
        switch error {
        case .gameOver:
            return "游戏已经结束"
        case .notPlayersTurn:
            return "还没轮到你"
        case .illegalAction:
            return "当前不能这样出"
        case .cardsNotInHand:
            return "选中的牌不在手牌中"
        case .invalidCombination:
            return "不是合法牌型"
        case .cannotBeatPrevious:
            return "压不住上一手"
        case .cannotPassOnLead:
            return "起手不能过"
        case .firstPlayMustContainSpadeThree:
            return "第一手必须带黑桃3"
        }
    }
}
