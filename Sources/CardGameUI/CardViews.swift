import SwiftUI

struct PlayedCardsFan: View {
    let cards: [Card]

    var body: some View {
        GeometryReader { proxy in
            let metrics = cardMetrics(width: proxy.size.width, count: cards.count)
            HStack(spacing: metrics.spacing) {
                ForEach(cards) { card in
                    PlayingCardView(
                        card: card,
                        selected: false,
                        compact: true,
                        width: metrics.cardWidth,
                        height: metrics.cardHeight
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    private func cardMetrics(width: CGFloat, count: Int) -> (cardWidth: CGFloat, cardHeight: CGFloat, spacing: CGFloat) {
        guard count > 0 else {
            return (34, 48, 0)
        }

        let cardWidth = min(36, max(22, width / CGFloat(count) * 1.75))
        let cardHeight = cardWidth * 1.38
        guard count > 1 else {
            return (cardWidth, cardHeight, 0)
        }

        let visibleStep = (width - cardWidth) / CGFloat(count - 1)
        let spacing = min(2, max(-18, visibleStep - cardWidth))
        return (cardWidth, cardHeight, spacing)
    }
}

struct HandSpreadView: View {
    let cards: [Card]
    let selectedCards: Set<Card>
    var markedCards: Set<Card> = []
    let onTap: (Card) -> Void
    let onSelectCards: ([Card]) -> Void

    @State private var gestureStart: CGPoint?
    @State private var isSwipeSelecting = false
    @State private var swipeSelectedIDs: Set<String> = []
    @State private var lastSwipeIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let metrics = handMetrics(width: proxy.size.width, count: cards.count)
            let selectedIDs = Set(selectedCards.map(\.id))
            let markedIDs = Set(markedCards.map(\.id))
            HStack(spacing: metrics.spacing) {
                ForEach(cards) { card in
                    PlayingCardView(
                        card: card,
                        selected: selectedIDs.contains(card.id),
                        marked: markedIDs.contains(card.id),
                        compact: false,
                        width: metrics.cardWidth,
                        height: metrics.cardHeight
                    )
                    .equatable()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleGestureChange(
                            value,
                            width: proxy.size.width,
                            metrics: metrics
                        )
                    }
                    .onEnded { value in
                        handleGestureEnd(
                            value,
                            width: proxy.size.width,
                            metrics: metrics
                        )
                    }
            )
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

    private func handleGestureChange(
        _ value: DragGesture.Value,
        width: CGFloat,
        metrics: (cardWidth: CGFloat, cardHeight: CGFloat, spacing: CGFloat)
    ) {
        if gestureStart == nil {
            gestureStart = value.startLocation
        }

        let horizontalDistance = abs(value.location.x - value.startLocation.x)
        let verticalDistance = abs(value.location.y - value.startLocation.y)
        if horizontalDistance > 10 || verticalDistance > 10 {
            isSwipeSelecting = true
        }

        guard isSwipeSelecting,
              let index = cardIndex(at: value.location, width: width, metrics: metrics)
        else { return }
        guard lastSwipeIndex != index || swipeSelectedIDs.isEmpty else { return }

        selectRange(endingAt: index)
    }

    private func handleGestureEnd(
        _ value: DragGesture.Value,
        width: CGFloat,
        metrics: (cardWidth: CGFloat, cardHeight: CGFloat, spacing: CGFloat)
    ) {
        defer {
            gestureStart = nil
            isSwipeSelecting = false
            swipeSelectedIDs.removeAll()
            lastSwipeIndex = nil
        }

        guard !isSwipeSelecting,
              let card = card(at: value.location, width: width, metrics: metrics)
        else { return }

        onTap(card)
    }

    private func card(
        at location: CGPoint,
        width: CGFloat,
        metrics: (cardWidth: CGFloat, cardHeight: CGFloat, spacing: CGFloat)
    ) -> Card? {
        guard let index = cardIndex(at: location, width: width, metrics: metrics) else { return nil }
        return cards[index]
    }

    private func cardIndex(
        at location: CGPoint,
        width: CGFloat,
        metrics: (cardWidth: CGFloat, cardHeight: CGFloat, spacing: CGFloat)
    ) -> Int? {
        guard !cards.isEmpty else { return nil }
        let step = max(1, metrics.cardWidth + metrics.spacing)
        let totalWidth = metrics.cardWidth + CGFloat(max(0, cards.count - 1)) * step
        let leftInset = max(0, (width - totalWidth) / 2)
        let localX = min(max(location.x - leftInset, 0), totalWidth)
        return min(cards.count - 1, max(0, Int(localX / step)))
    }

    private func selectRange(endingAt index: Int) {
        let start = lastSwipeIndex ?? index
        let lower = min(start, index)
        let upper = max(start, index)
        var cardsToSelect: [Card] = []

        for cardIndex in lower...upper {
            let card = cards[cardIndex]
            guard !swipeSelectedIDs.contains(card.id) else { continue }
            swipeSelectedIDs.insert(card.id)
            cardsToSelect.append(card)
        }

        if !cardsToSelect.isEmpty {
            onSelectCards(cardsToSelect)
        }
        lastSwipeIndex = index
    }
}

struct PlayingCardView: View, Equatable {
    let card: Card
    let selected: Bool
    var marked: Bool = false
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
        .background(
            LinearGradient(
                colors: [
                    .white,
                    Color(red: 0.93, green: 0.94, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(card.isRed ? .red : .black)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(cardBorderColor, lineWidth: selected ? 3 : (marked ? 2 : 1))
        )
        .shadow(color: .black.opacity(0.28), radius: selected ? 8 : 2, y: selected ? 5 : 1)
        .offset(y: selected ? -9 : 0)
        .animation(.snappy(duration: 0.16), value: selected)
    }

    private var cardBorderColor: Color {
        if selected {
            return Color(red: 0.98, green: 0.77, blue: 0.18)
        }
        if marked {
            return Color(red: 0.96, green: 0.54, blue: 0.08)
        }
        return .black.opacity(0.15)
    }

    static func == (lhs: PlayingCardView, rhs: PlayingCardView) -> Bool {
        lhs.card.id == rhs.card.id &&
            lhs.selected == rhs.selected &&
            lhs.marked == rhs.marked &&
            lhs.compact == rhs.compact &&
            lhs.width == rhs.width &&
            lhs.height == rhs.height
    }
}
