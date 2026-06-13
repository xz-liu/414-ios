import Foundation
import SwiftUI

@MainActor
final class DouDizhuViewModel: ObservableObject {
    @Published var selectedCards: Set<Card> = []
    @Published var notice: String = ""
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
        state.hands[0]
    }

    var bottomCardsVisible: [Card] {
        state.landlordIndex == nil ? [] : state.bottomCards
    }

    var isHumanTurn: Bool {
        state.currentPlayerIndex == 0 && !state.isGameOver && state.phase != .noLandlord
    }

    var canHint: Bool {
        isHumanTurn && state.phase == .playing
    }

    var canPlay: Bool {
        isHumanTurn && state.phase == .playing && !selectedCards.isEmpty
    }

    var canPassPlay: Bool {
        guard isHumanTurn, state.phase == .playing else { return false }
        return state.lastPlay != nil && state.lastPlay?.playerIndex != 0
    }

    var canBid: Bool {
        isHumanTurn && state.phase == .bidding
    }

    var legalBidValues: [Int] {
        engine.legalBidActions(for: 0).compactMap { action in
            if case .bid(let value) = action { return value }
            return nil
        }
    }

    var promptText: String {
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
        selectedCards.removeAll()
        notice = ""
        engine = DouDizhuGameEngine()
        audio.play(.shuffle)
        advanceAIIfNeeded()
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
        state.hands.indices.contains(playerIndex) ? state.hands[playerIndex].count : 0
    }

    func tableRecord(for playerIndex: Int) -> DouDizhuPlayRecord? {
        state.tableRecords.indices.contains(playerIndex) ? state.tableRecords[playerIndex] : nil
    }

    func statusText(for playerIndex: Int) -> String {
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
    func applyBid(_ action: DouDizhuBidAction) {
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
        guard !isAdvancingAI else { return }
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
