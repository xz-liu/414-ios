import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameViewModel()

    var body: some View {
        ZStack {
            tableBackground
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    topBar
                    tableRow
                        .frame(maxHeight: .infinity)
                    bottomRow
                }
                .padding(.horizontal, horizontalPadding(for: proxy.size))
                .padding(.vertical, 8)
            }
            if let banner = model.actionBanner {
                ActionBannerView(banner: banner)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: model.actionBanner?.id)
    }

    private var tableBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.32, blue: 0.20),
                Color(red: 0.02, green: 0.17, blue: 0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("414 Poker")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(promptText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Stepper(value: $model.deckCount, in: 1...4) {
                Text("\(model.deckCount)副")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 108)
            .disabled(model.isDealing)

            Button {
                model.dealNewGame()
            } label: {
                Label(dealButtonTitle, systemImage: model.isWaiting ? "play.fill" : "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(model.isDealing)
        }
        .frame(height: 36)
    }

    private var tableRow: some View {
        ZStack {
            VStack(spacing: 8) {
                topAI(index: 2)
                tableCenter
            }
            .padding(.horizontal, 58)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                sideAI(index: 1)
                Spacer(minLength: 0)
                sideAI(index: 3)
            }
            .padding(.top, 42)
        }
    }

    private var tableCenter: some View {
        if model.isWaiting || model.isDealing {
            return AnyView(preGamePanel)
        }

        return AnyView(
        HStack(spacing: 10) {
            lastPlayView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.state.isGameOver {
                scoreView
                    .frame(width: 220)
            } else {
                eventLogView
                    .frame(width: 220)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        )
    }

    private var preGamePanel: some View {
        VStack(spacing: 12) {
            Text(model.isDealing ? "正在发牌" : "准备开始")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text(model.state.players[index].name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("\(model.visibleCardCount(for: index))")
                            .font(.title.weight(.black))
                            .foregroundStyle(.yellow)
                    }
                    .frame(width: 62, height: 58)
                    .background(.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if model.isWaiting {
                Button {
                    model.dealNewGame()
                } label: {
                    Label("发牌", systemImage: "play.fill")
                        .font(.headline.weight(.bold))
                        .frame(width: 150, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                ProgressView()
                    .tint(.white)
            }

            Text(model.notice.isEmpty ? "选择副牌数后发牌" : model.notice)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var lastPlayView: some View {
        VStack(spacing: 8) {
            Text(model.state.visibleRecord?.message ?? "等待出牌")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -8) {
                    ForEach(model.state.visibleRecord?.combination?.cards ?? []) { card in
                        PlayingCardView(card: card, selected: false, compact: true)
                    }
                }
                .padding(.horizontal, 4)
                .frame(minWidth: 120)
            }
            .frame(height: 54)

            if !model.notice.isEmpty {
                Text(model.notice)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
            }
        }
    }

    private var eventLogView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("牌局")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
            ForEach(Array(model.state.eventLog.suffix(5).enumerated()), id: \.offset) { _, record in
                Text(record.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .background(.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var bottomRow: some View {
        VStack(spacing: 6) {
            controls
                .frame(maxWidth: 560)
            handArea
        }
        .frame(height: 152)
    }

    private var handArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("你的手牌 \(model.visibleCardCount(for: 0))张")
                    .font(.caption.weight(.bold))
                Text(model.statusText(for: 0))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(model.isHumanTurn ? .yellow : .white.opacity(0.14))
                    .foregroundStyle(model.isHumanTurn ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
            .foregroundStyle(.white)

            HandSpreadView(cards: model.humanHand, selectedCards: model.selectedCards) { card in
                model.toggle(card)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 7) {
            actionButton("提示", icon: "lightbulb.fill", enabled: model.canHint) {
                model.hint()
            }
            actionButton("过", icon: "arrowshape.turn.up.forward.fill", enabled: model.canPass) {
                model.pass()
            }
            actionButton("叉", icon: "multiply", enabled: model.canCha) {
                model.cha()
            }
            actionButton("勾", icon: "checkmark", enabled: model.canGou) {
                model.gou()
            }
            actionButton("出牌", icon: "paperplane.fill", enabled: model.canPlay) {
                model.playSelected()
            }
        }
    }

    private func sideAI(index: Int) -> some View {
        playerPanel(index: index)
            .frame(width: 74, height: 54)
    }

    private func topAI(index: Int) -> some View {
        playerPanel(index: index)
            .frame(width: 132, height: 44)
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
                    .foregroundStyle(highlighted ? .black : .white.opacity(0.75))
            }
        }
        .foregroundStyle(highlighted ? .black : .white)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(highlighted ? Color.yellow : Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func actionButton(
        _ title: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(enabled ? .blue : .gray)
        .disabled(!enabled)
    }

    private func horizontalPadding(for size: CGSize) -> CGFloat {
        size.width > 760 ? 14 : 8
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

private struct HandSpreadView: View {
    let cards: [Card]
    let selectedCards: Set<Card>
    let onTap: (Card) -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = handMetrics(width: proxy.size.width, count: cards.count)
            HStack(spacing: metrics.spacing) {
                ForEach(cards) { card in
                    PlayingCardView(
                        card: card,
                        selected: selectedCards.contains(card),
                        compact: false,
                        width: metrics.cardWidth,
                        height: metrics.cardHeight
                    )
                    .onTapGesture {
                        onTap(card)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
    }

    private func handMetrics(width: CGFloat, count: Int) -> (cardWidth: CGFloat, cardHeight: CGFloat, spacing: CGFloat) {
        guard count > 0 else {
            return (50, 72, 0)
        }

        let idealWidth: CGFloat = 50
        let minimumWidth: CGFloat = 30
        let scaledWidth = width / CGFloat(count) * 2.1
        let cardWidth = min(idealWidth, max(minimumWidth, scaledWidth))
        let cardHeight = cardWidth * 1.44

        guard count > 1 else {
            return (cardWidth, cardHeight, 0)
        }

        let visibleStep = (width - cardWidth) / CGFloat(count - 1)
        let spacing = min(3, visibleStep - cardWidth)
        return (cardWidth, cardHeight, spacing)
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.34), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.34), radius: 16, y: 8)
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

private struct PlayingCardView: View {
    let card: Card
    let selected: Bool
    let compact: Bool
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    var body: some View {
        let cardWidth = width ?? (compact ? 38 : 50)
        let cardHeight = height ?? (compact ? 52 : 72)
        let rankSize = max(9, min(compact ? 12 : 15, cardWidth * 0.31))
        let suitSize = max(9, min(compact ? 12 : 18, cardWidth * 0.34))

        VStack(alignment: .leading, spacing: 2) {
            Text(card.rank.label)
                .font(.system(size: rankSize, weight: .bold))
                .minimumScaleFactor(0.65)
            if let suit = card.suit {
                Text(suit.displaySymbol)
                    .font(.system(size: suitSize, weight: .semibold))
            } else {
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if !compact && cardWidth >= 40 {
                Text("#\(card.deckIndex + 1)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(compact ? 5 : 6)
        .frame(width: cardWidth, height: cardHeight)
        .background(.white)
        .foregroundStyle(card.isRed ? .red : .black)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(selected ? .yellow : .black.opacity(0.15), lineWidth: selected ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.22), radius: selected ? 6 : 2, y: selected ? 4 : 1)
        .offset(y: selected ? -9 : 0)
        .animation(.snappy(duration: 0.16), value: selected)
    }
}
