import SwiftUI

struct FourFourteenTableView: View {
    @StateObject private var model = GameViewModel()
    var onExit: (() -> Void)?

    var body: some View {
        ZStack {
            CardTableBackground()
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    topBar
                    tableRow
                        .frame(maxHeight: .infinity)
                    bottomRow
                }
                .padding(.horizontal, horizontalPadding(for: proxy.size))
                .padding(.top, 8)
                .padding(.bottom, bottomInteractionPadding(for: proxy.safeAreaInsets.bottom))
            }
            if let banner = model.actionBanner {
                ActionBannerView(banner: banner)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: model.actionBanner?.id)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            if let onExit {
                topIconButton(icon: "chevron.left", active: false) {
                    onExit()
                }
            }

            HStack(spacing: 5) {
                Text("414")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.yellow)
                Text("Poker")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(width: 76, alignment: .leading)

            Text(promptText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            playerCountSelector

            aiStyleSelector

            deckStepper

            topDealButton

            topIconButton(
                icon: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                active: model.soundEnabled
            ) {
                model.toggleSound()
            }
            topIconButton(
                icon: model.musicEnabled ? "music.note" : "music.note.slash",
                active: model.musicEnabled
            ) {
                model.toggleMusic()
            }
        }
        .frame(height: 38)
    }

    private var tableRow: some View {
        ZStack(alignment: .top) {
            let seatCount = model.state.players.count
            tableCenter
                .padding(.horizontal, 56)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(model.isWaiting || model.isDealing ? 4 : 0)

            if seatCount == 4 {
                topAI(index: 2)
                    .zIndex(2)
                    .allowsHitTesting(false)
            }

            HStack {
                sideAI(index: 1)
                Spacer(minLength: 0)
                sideAI(index: seatCount == 4 ? 3 : 2)
            }
            .padding(.horizontal, 58)
            .padding(.top, seatCount == 4 ? 18 : 10)
            .zIndex(2)
            .allowsHitTesting(false)
        }
    }

    private var tableCenter: some View {
        if model.isWaiting || model.isDealing {
            return AnyView(preGamePanel)
        }

        return AnyView(tablePlayGrid)
    }

    private var tablePlayGrid: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let seatCount = model.state.players.count
            ZStack {
                TableCenterSurface(width: width, height: height)

                if model.state.isGameOver {
                    scoreView
                        .frame(width: min(300, width * 0.48), height: min(132, height * 0.72))
                        .zIndex(3)
                } else {
                    tableCenterHint
                        .frame(width: min(260, width * 0.42))
                        .position(x: width * 0.50, y: height * 0.52)
                }

                tablePlaySlot(index: 1, width: min(238, width * 0.34))
                    .position(
                        x: seatCount == 4 ? width * 0.27 : width * 0.30,
                        y: seatCount == 4 ? height * 0.50 : height * 0.43
                    )

                if seatCount == 4 {
                    tablePlaySlot(index: 2, width: min(260, width * 0.42))
                        .position(x: width * 0.50, y: min(58, height * 0.24))

                    tablePlaySlot(index: 3, width: min(238, width * 0.34))
                        .position(x: width * 0.73, y: height * 0.50)
                } else {
                    tablePlaySlot(index: 2, width: min(238, width * 0.34))
                        .position(x: width * 0.70, y: height * 0.43)
                }

                tablePlaySlot(index: 0, width: min(300, width * 0.48))
                    .position(x: width * 0.50, y: max(height - 48, height * 0.74))

                TableEffectOverlay(effect: model.tableEffect, seatCount: seatCount)
                    .zIndex(5)
            }
        }
    }

    private var tableCenterHint: some View {
        VStack(spacing: 5) {
            Text(model.notice.isEmpty ? promptText : model.notice)
                .font(.caption.weight(.bold))
                .foregroundStyle(model.notice.isEmpty ? .white.opacity(0.56) : .yellow)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .shadow(color: .black.opacity(0.52), radius: 5, y: 2)
    }

    @ViewBuilder
    private func tablePlaySlot(index: Int, width: CGFloat) -> some View {
        if model.state.players.indices.contains(index) {
            TablePlaySlotView(
                playerName: model.state.players[index].name,
                record: model.tableRecord(for: index)
            )
            .frame(width: width, height: 76)
        } else {
            Color.clear.frame(width: width, height: 76)
        }
    }

    private var preGamePanel: some View {
        GeometryReader { proxy in
            ZStack {
                TableCenterSurface(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 12) {
                    Text(model.isDealing ? "正在发牌" : "准备开始")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 3)

                    HStack(spacing: 18) {
                        ForEach(model.state.players.indices, id: \.self) { index in
                            VStack(spacing: 2) {
                                Text(model.state.players[index].name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("\(model.visibleCardCount(for: index))")
                                    .font(.title.weight(.black))
                                    .foregroundStyle(.yellow)
                                    .shadow(color: .yellow.opacity(0.36), radius: 8)
                            }
                            .frame(width: 62, height: 56)
                        }
                    }

                    if model.isWaiting {
                        Button {
                            model.dealNewGame()
                        } label: {
                            Label("发牌", systemImage: "play.fill")
                                .font(.headline.weight(.black))
                                .frame(width: 150, height: 44)
                                .foregroundStyle(Color(red: 1.00, green: 0.56, blue: 0.12))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .shadow(color: Color.orange.opacity(0.82), radius: 8)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(model.notice.isEmpty ? "选择副牌数后发牌" : model.notice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var scoreView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("结算")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
            ForEach(model.state.scores, id: \.playerIndex) { score in
                HStack(spacing: 6) {
                    Text(score.playerName)
                        .frame(width: 56, alignment: .leading)
                    Spacer()
                    if score.penalty == 0 {
                        Text("赢家")
                    } else {
                        Text("\(score.remainingCards)张 x\(score.multiplier) = \(score.penalty)")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(score.penalty == 0 ? .yellow : .white)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .shadow(color: .black.opacity(0.60), radius: 6, y: 3)
    }

    private var bottomRow: some View {
        VStack(spacing: 4) {
            controls
                .frame(maxWidth: 560)
            handArea
        }
        .frame(height: bottomRowHeight)
    }

    private var handArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            HandSpreadView(
                cards: model.humanHand,
                selectedCards: model.selectedCards,
                markedCards: Set(model.humanRocket414Cards ?? [])
            ) { card in
                model.toggle(card)
            } onFlipCards: { cards in
                model.flipSelection(cards)
            }
            .frame(height: handSpreadHeight)

            HStack(spacing: 7) {
                Text("\(model.visibleCardCount(for: 0))张")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(model.statusText(for: 0))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(model.isHumanTurn ? .yellow : .white.opacity(0.86))
                    .shadow(color: model.isHumanTurn ? .yellow.opacity(0.55) : .clear, radius: 8)
                if model.humanRocket414Count > 0 {
                    rocket414Badge
                }
                if !model.selectedCards.isEmpty {
                    clearSelectionButton
                }
                Spacer(minLength: 0)
            }
            .frame(height: 18)
            .padding(.horizontal, 8)
        }
    }

    private var rocket414Badge: some View {
        Button {
            model.selectRocket414()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))
                Text(model.humanRocket414Count > 1 ? "4A4x\(model.humanRocket414Count)" : "4A4")
                    .font(.caption2.weight(.black))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color(red: 1.00, green: 0.68, blue: 0.08))
            .opacity(model.canSelectRocket414 ? 1 : 0.58)
            .shadow(color: Color.orange.opacity(model.canSelectRocket414 ? 0.74 : 0.20), radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSelectRocket414)
    }

    private var clearSelectionButton: some View {
        Button {
            model.clearSelection()
        } label: {
            Label("取消", systemImage: "xmark.circle.fill")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: .black.opacity(0.48), radius: 4, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var handSpreadHeight: CGFloat {
        model.visibleCardCount(for: 0) > 22 ? 104 : 82
    }

    private var bottomRowHeight: CGFloat {
        model.visibleCardCount(for: 0) > 22 ? 164 : 138
    }

    private var controls: some View {
        HStack(spacing: 7) {
            actionButton(model.isHinting ? "提示中" : "提示", icon: "lightbulb.fill", enabled: model.canHint, tint: Color(red: 0.20, green: 0.48, blue: 0.95)) {
                model.hint()
            }
            actionButton("过", icon: "arrowshape.turn.up.forward.fill", enabled: model.canPass, tint: Color(red: 0.34, green: 0.38, blue: 0.45)) {
                model.pass()
            }
            actionButton("叉", icon: "multiply", enabled: model.canCha, tint: Color(red: 0.82, green: 0.12, blue: 0.08)) {
                model.cha()
            }
            actionButton("勾", icon: "checkmark", enabled: model.canGou, tint: Color(red: 0.92, green: 0.47, blue: 0.08)) {
                model.gou()
            }
            actionButton("出牌", icon: "paperplane.fill", enabled: model.canPlay, tint: Color(red: 0.03, green: 0.45, blue: 0.26)) {
                model.playSelected()
            }
        }
    }

    private func sideAI(index: Int) -> some View {
        playerPanel(index: index)
            .frame(width: 68, height: 48)
    }

    private func topAI(index: Int) -> some View {
        playerPanel(index: index)
            .frame(width: 126, height: 40)
    }

    private func playerPanel(index: Int) -> some View {
        let highlighted = !model.isWaiting && !model.isDealing && model.state.prompt.playerIndex == index
        return VStack(spacing: 2) {
            Text(model.state.players[index].name)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 4) {
                Text("\(model.visibleCardCount(for: index))张")
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                Text(model.statusText(for: index))
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(highlighted ? .yellow : .white.opacity(0.75))
            }
        }
        .foregroundStyle(highlighted ? .yellow : .white)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: highlighted ? .yellow.opacity(0.62) : .black.opacity(0.55), radius: highlighted ? 7 : 4, y: 2)
    }

    private func actionButton(
        _ title: String,
        icon: String,
        enabled: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .foregroundStyle(enabled ? .white : .white.opacity(0.34))
                .shadow(color: enabled ? tint.opacity(0.82) : .clear, radius: 6)
                .shadow(color: .black.opacity(enabled ? 0.36 : 0.16), radius: 2, y: 1)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(enabled ? tint.opacity(0.95) : Color.white.opacity(0.12))
                        .frame(height: enabled ? 3 : 1)
                }
                .overlay(alignment: .top) {
                    if enabled {
                        Rectangle()
                            .fill(tint.opacity(0.70))
                            .frame(height: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func topIconButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(active ? Color(red: 1.00, green: 0.72, blue: 0.16) : .white.opacity(0.82))
                .frame(width: 34, height: 32)
                .shadow(color: active ? Color.orange.opacity(0.72) : .black.opacity(0.32), radius: active ? 6 : 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var playerCountSelector: some View {
        HStack(spacing: 5) {
            settingTextButton("3人", active: model.playerCount == 3, enabled: !model.isDealing) {
                model.setPlayerCount(3)
            }
            settingTextButton("4人", active: model.playerCount == 4, enabled: !model.isDealing) {
                model.setPlayerCount(4)
            }
        }
        .frame(width: 74, height: 34)
    }

    private var aiStyleSelector: some View {
        HStack(spacing: 5) {
            settingTextButton("休闲", active: model.aiStyle == .relaxed, enabled: !model.isDealing) {
                model.setAIStyle(.relaxed)
            }
            settingTextButton("竞技", active: model.aiStyle == .competitive, enabled: !model.isDealing) {
                model.setAIStyle(.competitive)
            }
        }
        .frame(width: 94, height: 34)
    }

    private func settingTextButton(
        _ title: String,
        active: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(active ? Color(red: 1.00, green: 0.82, blue: 0.22) : .white.opacity(enabled ? 0.58 : 0.26))
                .frame(maxWidth: .infinity, minHeight: 30)
                .shadow(color: active ? Color.yellow.opacity(0.64) : .clear, radius: 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var deckStepper: some View {
        HStack(spacing: 2) {
            deckAdjustButton(icon: "minus", enabled: !model.isDealing && model.deckCount > 1) {
                model.setDeckCount(model.deckCount - 1)
            }
            Text("\(model.deckCount)副")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42)
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            deckAdjustButton(icon: "plus", enabled: !model.isDealing && model.deckCount < 3) {
                model.setDeckCount(model.deckCount + 1)
            }
        }
        .frame(width: 108, height: 34)
    }

    private func deckAdjustButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(enabled ? Color(red: 1.00, green: 0.82, blue: 0.32) : .white.opacity(0.28))
                .frame(width: 28, height: 32)
                .shadow(color: enabled ? Color.yellow.opacity(0.62) : .clear, radius: 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var topDealButton: some View {
        Button {
            model.dealNewGame()
        } label: {
            Label(dealButtonTitle, systemImage: model.isWaiting ? "play.fill" : "arrow.clockwise")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .frame(width: 78, height: 34)
                .foregroundStyle(model.isDealing ? .white.opacity(0.40) : Color(red: 1.00, green: 0.56, blue: 0.12))
                .shadow(color: model.isDealing ? .clear : Color.orange.opacity(0.82), radius: 7)
                .shadow(color: .black.opacity(model.isDealing ? 0.15 : 0.34), radius: 2, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isDealing)
    }

    private func horizontalPadding(for size: CGSize) -> CGFloat {
        size.width > 760 ? 14 : 8
    }

    private func bottomInteractionPadding(for safeAreaBottom: CGFloat) -> CGFloat {
        max(22, safeAreaBottom + 18)
    }

    private var dealButtonTitle: String {
        switch model.phase {
        case .waiting:
            return "发牌"
        case .dealing:
            return "发牌中"
        case .playing:
            return "重发"
        }
    }

    private var promptText: String {
        switch model.phase {
        case .waiting:
            return "点发牌开始"
        case .dealing:
            return "正在发牌..."
        case .playing:
            break
        }
        guard let playerIndex = model.state.prompt.playerIndex else {
            return "游戏结束"
        }
        let playerName = model.state.players[playerIndex].name
        switch model.state.prompt.kind {
        case .lead:
            return "\(playerName)起手"
        case .follow:
            return "\(playerName)跟牌或过"
        case .cha:
            if model.state.players[playerIndex].isHuman {
                return "\(playerName)可以叉\(model.state.prompt.baseRank?.label ?? "")"
            }
            return "\(playerName)思考中"
        case .gou:
            if model.state.players[playerIndex].isHuman {
                return "\(playerName)可以勾\(model.state.prompt.baseRank?.label ?? "")"
            }
            return "\(playerName)思考中"
        case .gameOver:
            return "游戏结束"
        }
    }
}

private struct TablePlaySlotView: View {
    let playerName: String
    let record: PlayRecord?

    var body: some View {
        Group {
            if let record {
                VStack(spacing: 4) {
                    Text(title(for: record))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(titleColor(for: record))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if let cards = record.combination?.cards, !cards.isEmpty {
                        PlayedCardsFan(cards: cards)
                            .frame(height: 52)
                    } else {
                        Text("过")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white.opacity(0.70))
                            .frame(height: 52)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .shadow(color: slotGlowColor(for: record).opacity(record.kind == .pass ? 0.26 : 0.52), radius: 5)
                .shadow(color: .black.opacity(0.46), radius: 3, y: 2)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                Color.clear
            }
        }
    }

    private func title(for record: PlayRecord) -> String {
        switch record.kind {
        case .normal:
            return "\(playerName) · \(record.combination?.displayName ?? "出牌")"
        case .pass:
            return "\(playerName) · 过"
        case .cha:
            return "\(playerName) · 叉"
        case .gou:
            return "\(playerName) · 勾"
        case .system:
            return record.message
        }
    }

    private func titleColor(for record: PlayRecord) -> Color {
        switch record.kind {
        case .cha:
            return Color(red: 1.00, green: 0.35, blue: 0.28)
        case .gou:
            return Color(red: 1.00, green: 0.64, blue: 0.16)
        case .pass:
            return .white.opacity(0.62)
        case .normal, .system:
            return .white.opacity(0.88)
        }
    }

    private func slotGlowColor(for record: PlayRecord) -> Color {
        switch record.kind {
        case .cha:
            return Color(red: 1.00, green: 0.18, blue: 0.10)
        case .gou:
            return Color(red: 1.00, green: 0.58, blue: 0.12)
        case .normal, .system:
            return Color.black
        case .pass:
            return .white
        }
    }
}

private struct ActionBannerView: View {
    let banner: ActionBanner

    var body: some View {
        VStack(spacing: 5) {
            Text(banner.text)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(banner.subtitle)
                .font(.headline.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .frame(minWidth: 150)
        .shadow(color: backgroundColor.opacity(0.90), radius: 8)
        .shadow(color: .black.opacity(0.62), radius: 8, y: 5)
    }

    private var fontSize: CGFloat {
        switch banner.kind {
        case .cha, .gou:
            return 76
        case .deal:
            return 48
        case .pass:
            return 54
        case .play:
            return 42
        }
    }

    private var backgroundColor: Color {
        switch banner.kind {
        case .deal:
            return Color(red: 0.10, green: 0.43, blue: 0.26)
        case .cha:
            return Color(red: 0.76, green: 0.08, blue: 0.05)
        case .gou:
            return Color(red: 0.88, green: 0.48, blue: 0.04)
        case .pass:
            return Color(red: 0.19, green: 0.22, blue: 0.27)
        case .play:
            return Color(red: 0.09, green: 0.25, blue: 0.55)
        }
    }
}
