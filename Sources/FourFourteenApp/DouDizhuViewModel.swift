import Foundation
import SwiftUI

@MainActor
final class DouDizhuViewModel: ObservableObject {
    @Published var selectedCards: Set<Card> = []
    @Published var notice: String = ""
    @Published var phase: GamePhase = .waiting
    @Published var visibleHandCounts: [Int] = [0, 0, 0]
    @Published var soundEnabled = true {
        didSet {
            audio.effectsEnabled = soundEnabled
        }
    }
    @Published var musicEnabled = false {
        didSet {
            audio.setMusicEnabled(musicEnabled)
        }
    }

    private(set) var engine = DouDizhuGameEngine()
    private var isAdvancingAI = false
    private let audio = AudioController()

    var state: DouDizhuState {
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

    var bottomCardsVisible: [Card] {
        phase == .playing && state.landlordIndex != nil ? state.bottomCards : []
    }

    var isHumanTurn: Bool {
        phase == .playing && state.currentPlayerIndex == 0 && !state.isGameOver && state.phase != .noLandlord
    }

    var isWaiting: Bool {
        phase == .waiting
    }

    var isDealing: Bool {
        phase == .dealing
    }

    var canHint: Bool {
        phase == .playing && isHumanTurn && state.phase == .playing
    }

    var canPlay: Bool {
        phase == .playing && isHumanTurn && state.phase == .playing && !selectedCards.isEmpty
    }

    var canPassPlay: Bool {
        guard phase == .playing, isHumanTurn, state.phase == .playing else { return false }
        return state.lastPlay != nil && state.lastPlay?.playerIndex != 0
    }

    var canBid: Bool {
        phase == .playing && isHumanTurn && state.phase == .bidding
    }

    var legalBidValues: [Int] {
        engine.legalBidActions(for: 0).compactMap { action in
            if case .bid(let value) = action { return value }
            return nil
        }
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
        switch state.phase {
        case .bidding:
            return "\(state.players[state.currentPlayerIndex].name)叫地主"
        case .playing:
            if state.currentPlayerIndex == 0 {
                return state.lastPlay == nil || state.lastPlay?.playerIndex == 0 ? "你出牌" : "你跟牌或过"
            }
            return "\(state.players[state.currentPlayerIndex].name)思考中"
        case .noLandlord:
            return "无人叫地主，请重发"
        case .gameOver:
            return state.winnerTeam == .landlord ? "地主胜利" : "农民胜利"
        }
    }

    func newGame() {
        dealNewGame()
    }

    func dealNewGame() {
        guard phase != .dealing else { return }
        selectedCards.removeAll()
        notice = ""
        engine = DouDizhuGameEngine()
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

    func bid(_ value: Int) {
        applyBid(.bid(value))
    }

    func passBid() {
        applyBid(.pass)
    }

    func playSelected() {
        applyPlay(.play(Array(selectedCards)))
    }

    func passPlay() {
        applyPlay(.pass)
    }

    func hint() {
        guard let action = DouDizhuHintEngine.bestAction(state: state, for: 0) else {
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

    func tableRecord(for playerIndex: Int) -> DouDizhuPlayRecord? {
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
        if state.landlordIndex == playerIndex {
            return "地主"
        }
        if state.landlordIndex != nil {
            return "农民"
        }
        if state.phase == .bidding, state.currentPlayerIndex == playerIndex {
            return state.players[playerIndex].isHuman ? "叫分" : "思考"
        }
        return "等待"
    }
}

private extension DouDizhuViewModel {
    func animateDeal() {
        notice = "正在发牌..."
        let targetCounts = engine.state.hands.map(\.count)
        let delay: UInt64 = 46_000_000

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

            notice = "开始叫地主"
            audio.play(.draw)
            try? await Task.sleep(nanoseconds: 620_000_000)
            phase = .playing
            notice = ""
            objectWillChange.send()
            advanceAIIfNeeded()
        }
    }

    func applyBid(_ action: DouDizhuBidAction) {
        guard phase == .playing else { return }
        do {
            try engine.applyBid(action)
            selectedCards.removeAll()
            notice = ""
            audio.play(.tap)
            advanceAIIfNeeded()
        } catch {
            notice = message(for: error)
            audio.play(.error)
        }
    }

    func applyPlay(_ action: DouDizhuAction) {
        guard phase == .playing else { return }
        do {
            try engine.applyPlay(action)
            selectedCards.removeAll()
            notice = ""
            playSoundForLatestEvent()
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
                  engine.state.phase != .noLandlord,
                  !engine.state.players[engine.state.currentPlayerIndex].isHuman {
                let playerIndex = engine.state.currentPlayerIndex
                notice = "\(engine.state.players[playerIndex].name)思考中..."
                try? await Task.sleep(nanoseconds: 850_000_000)
                do {
                    switch engine.state.phase {
                    case .bidding:
                        let action = DouDizhuAIPlayer().chooseBid(state: engine.state, for: playerIndex)
                        try engine.applyBid(action)
                        audio.play(.tap)
                    case .playing:
                        let action = DouDizhuAIPlayer().chooseAction(state: engine.state, for: playerIndex)
                        try engine.applyPlay(action)
                        playSoundForLatestEvent()
                    case .noLandlord, .gameOver:
                        break
                    }
                    notice = ""
                    try? await Task.sleep(nanoseconds: 750_000_000)
                } catch {
                    notice = message(for: error)
                    audio.play(.error)
                    break
                }
            }
        }
    }

    func playSoundForLatestEvent() {
        guard let record = engine.state.eventLog.last else { return }
        switch record.kind {
        case .play:
            if record.combination?.isBombLike == true {
                audio.play(.reaction)
            } else {
                audio.play(.playcard)
            }
        case .pass:
            audio.play(.pass)
        case .bid, .landlord, .system:
            audio.play(.tap)
        }
    }

    func message(for error: Error) -> String {
        guard let error = error as? DouDizhuError else {
            return "操作失败"
        }
        switch error {
        case .gameOver:
            return "游戏已经结束"
        case .notPlayersTurn:
            return "还没轮到你"
        case .wrongPhase:
            return "当前阶段不能这样操作"
        case .illegalBid:
            return "叫分必须更高"
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
        }
    }
}
