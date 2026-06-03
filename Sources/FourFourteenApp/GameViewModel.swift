import Foundation
import SwiftUI

struct ActionBanner: Identifiable, Equatable {
    enum Kind: Equatable {
        case deal
        case play
        case pass
        case cha
        case gou
    }

    let id = UUID()
    let text: String
    let subtitle: String
    let kind: Kind
}

enum GamePhase: Equatable {
    case waiting
    case dealing
    case playing
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published var deckCount: Int = 1
    @Published var selectedCards: Set<Card> = []
    @Published var notice: String = ""
    @Published var actionBanner: ActionBanner?
    @Published var phase: GamePhase = .waiting
    @Published var visibleHandCounts: [Int] = [0, 0, 0, 0]
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

    private(set) var engine: GameEngine
    private var isAdvancingAI = false
    private let audio = AudioController()

    init() {
        self.engine = GameEngine(deckCount: 1)
    }

    var state: GameState {
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
        phase == .playing && state.prompt.playerIndex == 0 && !state.isGameOver
    }

    var isWaiting: Bool {
        phase == .waiting
    }

    var isDealing: Bool {
        phase == .dealing
    }

    var canPlay: Bool {
        guard isHumanTurn, state.prompt.kind == .lead || state.prompt.kind == .follow else { return false }
        return !selectedCards.isEmpty
    }

    var canPass: Bool {
        guard isHumanTurn else { return false }
        return state.prompt.kind == .follow || state.prompt.kind == .cha || state.prompt.kind == .gou
    }

    var canHint: Bool {
        isHumanTurn
    }

    var canCha: Bool {
        guard isHumanTurn, state.prompt.kind == .cha, let rank = state.prompt.baseRank else { return false }
        return RulesEngine.legalChaCards(in: state.hands[0], rank: rank) != nil
    }

    var canGou: Bool {
        guard isHumanTurn, state.prompt.kind == .gou, let rank = state.prompt.baseRank else { return false }
        return RulesEngine.legalGouCard(in: state.hands[0], rank: rank) != nil
    }

    var humanRocket414Cards: [Card]? {
        humanHand.rocket414Cards()
    }

    var humanRocket414Count: Int {
        humanHand.rocket414Count()
    }

    var canSelectRocket414: Bool {
        isHumanTurn && humanRocket414Cards != nil
    }

    func dealNewGame() {
        guard phase != .dealing else { return }
        selectedCards.removeAll()
        notice = ""
        actionBanner = nil
        audio.play(.shuffle)
        engine = GameEngine(deckCount: deckCount)
        visibleHandCounts = [0, 0, 0, 0]
        phase = .dealing
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

    func select(_ card: Card) {
        guard isHumanTurn else { return }
        guard !selectedCards.contains(card) else { return }
        selectedCards.insert(card)
    }

    func select(_ cards: [Card]) {
        guard isHumanTurn else { return }
        let newCards = cards.filter { !selectedCards.contains($0) }
        guard !newCards.isEmpty else { return }
        selectedCards.formUnion(newCards)
    }

    func selectRocket414() {
        guard let cards = humanRocket414Cards else { return }
        selectedCards = Set(cards)
        notice = "已选中4A4火箭"
        audio.play(.tap)
    }

    func playSelected() {
        apply(.play(Array(selectedCards)))
    }

    func pass() {
        apply(.pass)
    }

    func cha() {
        if selectedCards.count == 2 {
            apply(.cha(Array(selectedCards)))
            return
        }
        if let action = engine.legalActions(for: 0).first(where: {
            if case .cha = $0 { return true }
            return false
        }) {
            apply(action)
        }
    }

    func gou() {
        if selectedCards.count == 1, let card = selectedCards.first {
            apply(.gou(card))
            return
        }
        if let action = engine.legalActions(for: 0).first(where: {
            if case .gou = $0 { return true }
            return false
        }) {
            apply(action)
        }
    }

    func hint() {
        guard let action = HintEngine.bestAction(state: state, for: 0) else {
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
        guard let promptPlayer = state.prompt.playerIndex else {
            return state.isGameOver ? "结束" : "等待"
        }
        if promptPlayer == playerIndex {
            switch state.prompt.kind {
            case .lead: return "起手"
            case .follow: return "跟牌"
            case .cha: return state.players[playerIndex].isHuman ? "可叉" : "思考"
            case .gou: return state.players[playerIndex].isHuman ? "可勾" : "思考"
            case .gameOver: return "结束"
            }
        }
        return "等待"
    }

    func visibleCardCount(for playerIndex: Int) -> Int {
        switch phase {
        case .waiting:
            return 0
        case .dealing:
            return visibleHandCounts.indices.contains(playerIndex) ? visibleHandCounts[playerIndex] : 0
        case .playing:
            return state.hands[playerIndex].count
        }
    }
}

private extension GameViewModel {
    func animateDeal() {
        actionBanner = ActionBanner(text: "发牌", subtitle: "\(deckCount)副牌", kind: .deal)
        notice = "正在发牌..."
        let targetCounts = engine.state.hands.map(\.count)
        let delay = UInt64(max(18_000_000, 58_000_000 / UInt64(deckCount)))

        Task { @MainActor in
            var remaining = targetCounts.reduce(0, +)
            while remaining > 0 {
                for playerIndex in targetCounts.indices where visibleHandCounts[playerIndex] < targetCounts[playerIndex] {
                    withAnimation(.easeOut(duration: 0.12)) {
                        visibleHandCounts[playerIndex] += 1
                    }
                    remaining -= 1
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            notice = "发牌完成"
            audio.play(.draw)
            actionBanner = ActionBanner(text: "开始", subtitle: promptSummary, kind: .deal)
            try? await Task.sleep(nanoseconds: 850_000_000)
            phase = .playing
            actionBanner = nil
            notice = ""
            objectWillChange.send()
            advanceAIIfNeeded()
        }
    }

    func apply(_ action: PlayerAction) {
        guard phase == .playing else { return }
        do {
            let eventCountBefore = engine.state.eventLog.count
            try engine.apply(action)
            selectedCards.removeAll()
            notice = ""
            if engine.state.eventLog.count > eventCountBefore {
                showBannerFromLatestEvent()
                playSoundForLatestEvent()
            }
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
            while let playerIndex = engine.state.prompt.playerIndex,
                  phase == .playing,
                  !engine.state.players[playerIndex].isHuman,
                  !engine.state.isGameOver {
                notice = "\(engine.state.players[playerIndex].name)思考中..."
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let snapshot = engine.state
                let action = await Task.detached(priority: .userInitiated) {
                    AIPlayer().chooseAction(state: snapshot, for: playerIndex)
                }.value
                guard phase == .playing, engine.state == snapshot else {
                    continue
                }
                do {
                    let eventCountBefore = engine.state.eventLog.count
                    try engine.apply(action)
                    notice = ""
                    if engine.state.eventLog.count > eventCountBefore {
                        showBannerFromLatestEvent(autoClear: false)
                        playSoundForLatestEvent()
                    }
                    objectWillChange.send()
                    let pause = latestEventIsReaction ? 1_850_000_000 : 1_250_000_000
                    try? await Task.sleep(nanoseconds: UInt64(pause))
                } catch {
                    notice = message(for: error)
                    audio.play(.error)
                    break
                }
            }
            clearBanner()
        }
    }

    func showBannerFromLatestEvent(autoClear: Bool = true) {
        guard let record = engine.state.eventLog.last,
              let banner = banner(for: record)
        else { return }
        actionBanner = banner
        guard autoClear else { return }
        let bannerID = banner.id
        Task { @MainActor in
            let duration: UInt64 = (banner.kind == .cha || banner.kind == .gou) ? 1_650_000_000 : 950_000_000
            try? await Task.sleep(nanoseconds: duration)
            if actionBanner?.id == bannerID {
                actionBanner = nil
            }
        }
    }

    func clearBanner() {
        actionBanner = nil
    }

    func banner(for record: PlayRecord) -> ActionBanner? {
        switch record.kind {
        case .normal:
            guard let combination = record.combination else { return nil }
            return ActionBanner(
                text: combination.displayName,
                subtitle: record.playerName,
                kind: .play
            )
        case .pass:
            return ActionBanner(text: "过", subtitle: record.playerName, kind: .pass)
        case .cha:
            return ActionBanner(text: "叉!", subtitle: record.playerName, kind: .cha)
        case .gou:
            return ActionBanner(text: "勾!", subtitle: record.playerName, kind: .gou)
        case .system:
            if record.message.contains("死叉") {
                return ActionBanner(text: "死叉", subtitle: record.message, kind: .cha)
            }
            if record.message.contains("重新起手") {
                return ActionBanner(text: "重起", subtitle: record.message, kind: .play)
            }
            return nil
        }
    }

    var latestEventIsReaction: Bool {
        guard let kind = engine.state.eventLog.last?.kind else { return false }
        return kind == .cha || kind == .gou
    }

    func playSoundForLatestEvent() {
        guard let record = engine.state.eventLog.last else { return }
        switch record.kind {
        case .normal:
            audio.play(.playcard)
        case .pass:
            audio.play(.pass)
        case .cha, .gou:
            audio.play(.reaction)
        case .system:
            if record.message.contains("死叉") || record.message.contains("重新起手") {
                audio.play(.reaction)
            } else {
                audio.play(.tap)
            }
        }
    }

    var promptSummary: String {
        guard let playerIndex = engine.state.prompt.playerIndex else {
            return "游戏开始"
        }
        return "\(engine.state.players[playerIndex].name)先出"
    }

    func message(for error: Error) -> String {
        guard let gameError = error as? GameError else {
            return "操作失败"
        }
        switch gameError {
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
            return "起手必须出牌"
        }
    }
}
