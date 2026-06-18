import SwiftUI

struct DouDizhuTableView: View {
    @StateObject private var model = DouDizhuViewModel()
    let onExit: () -> Void

    var body: some View {
        ZStack {
            CardTableBackground()
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    topBar
                    tableArea
                        .frame(maxHeight: .infinity)
                    bottomArea
                }
                .padding(.horizontal, proxy.size.width > 760 ? 14 : 8)
                .padding(.top, 8)
                .padding(.bottom, max(22, proxy.safeAreaInsets.bottom + 18))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            iconButton(icon: "chevron.left", active: false, action: onExit)

            HStack(spacing: 5) {
                Text("斗地主")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color(red: 1.00, green: 0.56, blue: 0.12))
                Text(roleText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(width: 110, alignment: .leading)

            Text(model.notice.isEmpty ? model.promptText : model.notice)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.notice.isEmpty ? .white.opacity(0.78) : .yellow)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            bottomCardsView

            topDealButton

            iconButton(
                icon: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                active: model.soundEnabled
            ) {
                model.toggleSound()
            }
            iconButton(
                icon: model.musicEnabled ? "music.note" : "music.note.slash",
                active: model.musicEnabled
            ) {
                model.toggleMusic()
            }
        }
        .frame(height: 36)
    }

    private var tableArea: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                TableCenterSurface(width: width, height: height)

                if model.isWaiting || model.isDealing {
                    preGamePanel
                        .frame(width: min(330, width * 0.62), height: min(150, height * 0.72))
                        .position(x: width * 0.50, y: height * 0.54)
                        .zIndex(3)
                } else if model.state.phase == .gameOver {
                    scoreView
                        .frame(width: min(340, width * 0.50), height: min(150, height * 0.72))
                        .position(x: width * 0.50, y: height * 0.52)
                        .zIndex(3)
                } else if model.state.phase == .noLandlord {
                    Text("无人叫地主，请重发")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.55), radius: 6, y: 3)
                        .position(x: width * 0.50, y: height * 0.52)
                } else {
                    Text(model.promptText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.56))
                        .shadow(color: .black.opacity(0.52), radius: 5, y: 2)
                        .position(x: width * 0.50, y: height * 0.52)
                }

                playerPanel(index: 1)
                    .frame(width: 92, height: 52)
                    .position(x: 74, y: 36)

                playerPanel(index: 2)
                    .frame(width: 92, height: 52)
                    .position(x: width - 74, y: 36)

                playSlot(index: 1, width: min(240, width * 0.34))
                    .position(x: width * 0.29, y: height * 0.45)

                playSlot(index: 2, width: min(240, width * 0.34))
                    .position(x: width * 0.71, y: height * 0.45)

                playSlot(index: 0, width: min(300, width * 0.48))
                    .position(x: width * 0.50, y: max(height - 42, height * 0.76))

                TableEffectOverlay(effect: model.tableEffect, seatCount: 3)
                    .zIndex(5)
            }
        }
    }

    private var bottomArea: some View {
        VStack(spacing: 4) {
            controls
                .frame(maxWidth: 560)
            VStack(alignment: .leading, spacing: 2) {
                HandSpreadView(
                    cards: model.humanHand,
                    selectedCards: model.selectedCards
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
                    if !model.selectedCards.isEmpty {
                        clearSelectionButton
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 18)
                .padding(.horizontal, 8)
            }
        }
        .frame(height: bottomAreaHeight)
    }

    private var handSpreadHeight: CGFloat {
        model.visibleCardCount(for: 0) > 22 ? 104 : 82
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

    private var bottomAreaHeight: CGFloat {
        model.visibleCardCount(for: 0) > 22 ? 164 : 138
    }

    private var controls: some View {
        Group {
            if model.phase != .playing {
                HStack(spacing: 7) {
                    actionButton(
                        model.isDealing ? "发牌中" : "发牌",
                        icon: model.isDealing ? "hourglass" : "play.fill",
                        enabled: model.isWaiting,
                        tint: Color(red: 1.00, green: 0.56, blue: 0.12)
                    ) {
                        model.dealNewGame()
                    }
                }
            } else if model.state.phase == .bidding {
                HStack(spacing: 7) {
                    actionButton("不叫", icon: "xmark", enabled: model.canBid, tint: Color(red: 0.34, green: 0.38, blue: 0.45)) {
                        model.passBid()
                    }
                    ForEach([1, 2, 3], id: \.self) { value in
                        actionButton("\(value)分", icon: "flag.fill", enabled: model.canBid && model.legalBidValues.contains(value), tint: bidColor(value)) {
                            model.bid(value)
                        }
                    }
                }
            } else {
                HStack(spacing: 7) {
                    actionButton("提示", icon: "lightbulb.fill", enabled: model.canHint, tint: Color(red: 0.20, green: 0.48, blue: 0.95)) {
                        model.hint()
                    }
                    actionButton("过", icon: "arrowshape.turn.up.forward.fill", enabled: model.canPassPlay, tint: Color(red: 0.34, green: 0.38, blue: 0.45)) {
                        model.passPlay()
                    }
                    actionButton("出牌", icon: "paperplane.fill", enabled: model.canPlay, tint: Color(red: 0.03, green: 0.45, blue: 0.26)) {
                        model.playSelected()
                    }
                }
            }
        }
    }

    private var bottomCardsView: some View {
        HStack(spacing: -12) {
            if model.bottomCardsVisible.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    cardBack
                }
            } else {
                ForEach(model.bottomCardsVisible) { card in
                    PlayingCardView(card: card, selected: false, compact: true, width: 26, height: 36)
                }
            }
        }
        .frame(width: 66, height: 34)
    }

    private var preGamePanel: some View {
        VStack(spacing: 10) {
            Text(model.isDealing ? "正在发牌" : "准备发牌")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.55), radius: 7, y: 3)

            HStack(spacing: 22) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(spacing: 2) {
                        Text(model.state.players[index].name)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                        Text("\(model.visibleCardCount(for: index))")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.yellow)
                            .shadow(color: .yellow.opacity(0.40), radius: 7)
                    }
                    .frame(width: 62)
                }
            }

            if model.isWaiting {
                Button {
                    model.dealNewGame()
                } label: {
                    Label("发牌", systemImage: "play.fill")
                        .font(.headline.weight(.black))
                        .frame(width: 142, height: 40)
                        .foregroundStyle(Color(red: 1.00, green: 0.56, blue: 0.12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shadow(color: Color.orange.opacity(0.82), radius: 8)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.82)
            }
        }
        .padding(12)
        .shadow(color: .black.opacity(0.58), radius: 8, y: 4)
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.28, blue: 0.55),
                        Color(red: 0.06, green: 0.12, blue: 0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .frame(width: 26, height: 36)
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
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
                    Text(score.team == .landlord ? "地主" : "农民")
                        .frame(width: 36, alignment: .leading)
                    Spacer()
                    Text(score.delta > 0 ? "+\(score.delta)" : "\(score.delta)")
                        .foregroundStyle(score.delta > 0 ? .yellow : .white.opacity(0.82))
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            }
            Text(model.state.scores.first?.notes.joined(separator: " · ") ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(8)
        .shadow(color: .black.opacity(0.60), radius: 6, y: 3)
    }

    private func playerPanel(index: Int) -> some View {
        let highlighted = model.phase == .playing && model.state.currentPlayerIndex == index && model.state.phase != .gameOver
        return VStack(spacing: 2) {
            Text(model.state.players[index].name)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text("\(model.visibleCardCount(for: index))张")
                    .font(.callout.weight(.black))
                Text(model.statusText(for: index))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(highlighted ? .yellow : .white.opacity(0.75))
            }
        }
        .foregroundStyle(highlighted ? .yellow : .white)
        .shadow(color: highlighted ? .yellow.opacity(0.62) : .black.opacity(0.55), radius: highlighted ? 7 : 4, y: 2)
    }

    private func playSlot(index: Int, width: CGFloat) -> some View {
        DouDizhuPlaySlotView(
            playerName: model.state.players[index].name,
            record: model.tableRecord(for: index)
        )
        .frame(width: width, height: 76)
    }

    private func iconButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func bidColor(_ value: Int) -> Color {
        switch value {
        case 1:
            return Color(red: 0.18, green: 0.48, blue: 0.78)
        case 2:
            return Color(red: 0.86, green: 0.45, blue: 0.12)
        default:
            return Color(red: 0.82, green: 0.12, blue: 0.08)
        }
    }

    private var roleText: String {
        guard model.phase == .playing else {
            return "待发牌"
        }
        guard let landlord = model.state.landlordIndex else { return "叫地主" }
        return landlord == 0 ? "你是地主" : "你是农民"
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
}

private struct DouDizhuPlaySlotView: View {
    let playerName: String
    let record: DouDizhuPlayRecord?

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
                        Text(record.kind == .pass ? "过" : "")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white.opacity(0.70))
                            .frame(height: 52)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .shadow(color: titleColor(for: record).opacity(record.kind == .pass ? 0.26 : 0.52), radius: 5)
                .shadow(color: .black.opacity(0.46), radius: 3, y: 2)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                Color.clear
            }
        }
    }

    private func title(for record: DouDizhuPlayRecord) -> String {
        switch record.kind {
        case .play:
            return "\(playerName) · \(record.combination?.displayName ?? "出牌")"
        case .pass:
            return "\(playerName) · 过"
        case .bid, .landlord, .system:
            return record.message
        }
    }

    private func titleColor(for record: DouDizhuPlayRecord) -> Color {
        switch record.kind {
        case .play:
            if record.combination?.isBombLike == true {
                return Color(red: 1.00, green: 0.35, blue: 0.28)
            }
            return .white.opacity(0.88)
        case .pass:
            return .white.opacity(0.62)
        case .bid, .landlord:
            return Color(red: 1.00, green: 0.64, blue: 0.16)
        case .system:
            return .yellow
        }
    }
}
