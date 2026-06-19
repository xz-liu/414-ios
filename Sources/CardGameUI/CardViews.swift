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

struct RevealedHandStrip: View {
    let playerName: String
    let cards: [Card]

    var body: some View {
        GeometryReader { proxy in
            let layout = revealedLayout(width: proxy.size.width, height: proxy.size.height, count: cards.count)
            VStack(spacing: 3) {
                Text(cards.isEmpty ? "\(playerName) · 已出完" : "\(playerName) · \(cards.count)张")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(cards.isEmpty ? .yellow : .white.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .shadow(color: .black.opacity(0.58), radius: 4, y: 2)

                if cards.isEmpty {
                    Text("WIN")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shadow(color: .yellow.opacity(0.55), radius: 6)
                } else {
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.rows.indices, id: \.self) { rowIndex in
                            let row = layout.rows[rowIndex]
                            HStack(spacing: row.spacing) {
                                ForEach(row.startIndex..<row.endIndex, id: \.self) { index in
                                    PlayingCardView(
                                        card: cards[index],
                                        selected: false,
                                        compact: true,
                                        width: layout.cardWidth,
                                        height: layout.cardHeight
                                    )
                                }
                            }
                            .frame(width: proxy.size.width, height: layout.cardHeight, alignment: .center)
                            .position(x: proxy.size.width / 2, y: row.y + layout.cardHeight / 2)
                            .zIndex(Double(rowIndex))
                        }
                    }
                    .frame(width: proxy.size.width, height: max(0, proxy.size.height - 15), alignment: .topLeading)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .shadow(color: .black.opacity(0.46), radius: 4, y: 2)
        }
    }

    private struct RevealedLayout {
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let rows: [RevealedRow]
    }

    private struct RevealedRow {
        let startIndex: Int
        let count: Int
        let y: CGFloat
        let spacing: CGFloat

        var endIndex: Int {
            startIndex + count
        }
    }

    private func revealedLayout(width: CGFloat, height: CGFloat, count: Int) -> RevealedLayout {
        guard count > 0 else {
            return RevealedLayout(cardWidth: 28, cardHeight: 38, rows: [])
        }

        let rowCount = count > 34 ? 3 : (count > 16 ? 2 : 1)
        let cardsPerRow = Int(ceil(Double(count) / Double(rowCount)))
        let cardWidth = min(30, max(18, width / CGFloat(max(cardsPerRow, 1)) * 1.72))
        let cardHeight = cardWidth * 1.38
        let availableHeight = max(0, height - 17)
        let rowStep = rowCount == 1 ? 0 : min(cardHeight + 2, max(cardHeight * 0.52, availableHeight / CGFloat(rowCount)))

        var rows: [RevealedRow] = []
        var startIndex = 0
        for rowIndex in 0..<rowCount where startIndex < count {
            let rowCountValue = min(cardsPerRow, count - startIndex)
            let spacing = spacing(width: width, cardWidth: cardWidth, count: rowCountValue)
            rows.append(
                RevealedRow(
                    startIndex: startIndex,
                    count: rowCountValue,
                    y: CGFloat(rowIndex) * rowStep,
                    spacing: spacing
                )
            )
            startIndex += rowCountValue
        }

        return RevealedLayout(cardWidth: cardWidth, cardHeight: cardHeight, rows: rows)
    }

    private func spacing(width: CGFloat, cardWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let visibleStep = (width - cardWidth) / CGFloat(count - 1)
        return min(2, max(-24, visibleStep - cardWidth))
    }
}

struct HandSpreadView: View {
    let cards: [Card]
    let selectedCards: Set<Card>
    var markedCards: Set<Card> = []
    let onTap: (Card) -> Void
    let onFlipCards: ([Card]) -> Void

    @State private var gestureStart: CGPoint?
    @State private var isSwipeSelecting = false
    @State private var swipeFlippedIDs: Set<String> = []
    @State private var lastSwipeIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let layout = handLayout(
                width: proxy.size.width,
                height: proxy.size.height,
                count: cards.count
            )
            let selectedIDs = Set(selectedCards.map(\.id))
            let markedIDs = Set(markedCards.map(\.id))

            ZStack(alignment: .topLeading) {
                ForEach(layout.rows.indices, id: \.self) { rowIndex in
                    let row = layout.rows[rowIndex]
                    HStack(spacing: row.spacing) {
                        ForEach(row.startIndex..<row.endIndex, id: \.self) { index in
                            let card = cards[index]
                            PlayingCardView(
                                card: card,
                                selected: selectedIDs.contains(card.id),
                                marked: markedIDs.contains(card.id),
                                compact: false,
                                width: layout.cardWidth,
                                height: layout.cardHeight
                            )
                            .equatable()
                        }
                    }
                    .frame(width: proxy.size.width, height: layout.cardHeight, alignment: .center)
                    .position(x: proxy.size.width / 2, y: row.y + layout.cardHeight / 2)
                    .zIndex(Double(rowIndex))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleGestureChange(
                            value,
                            layout: layout
                        )
                    }
                    .onEnded { value in
                        handleGestureEnd(
                            value,
                            layout: layout
                        )
                    }
            )
        }
    }

    private struct HandLayout {
        let width: CGFloat
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let rows: [HandRowLayout]
    }

    private struct HandRowLayout {
        let startIndex: Int
        let count: Int
        let y: CGFloat
        let spacing: CGFloat

        var endIndex: Int {
            startIndex + count
        }
    }

    private func handLayout(width: CGFloat, height: CGFloat, count: Int) -> HandLayout {
        guard count > 0 else {
            return HandLayout(width: width, cardWidth: 50, cardHeight: 72, rows: [])
        }

        let rowCount = count > 22 ? 2 : 1
        let firstRowCount = rowCount == 1 ? count : Int(ceil(Double(count) / 2.0))
        let secondRowCount = max(0, count - firstRowCount)
        let maxRowCount = max(firstRowCount, secondRowCount, 1)
        let idealWidth: CGFloat = rowCount == 1 ? 50 : 46
        let minimumWidth: CGFloat = rowCount == 1 ? 30 : 28
        let widthScale: CGFloat = rowCount == 1 ? 2.1 : 1.95
        let scaledWidth = width / CGFloat(maxRowCount) * widthScale
        let cardWidth = min(idealWidth, max(minimumWidth, scaledWidth))
        let cardHeight = cardWidth * (rowCount == 1 ? 1.44 : 1.36)

        func spacing(for rowCardCount: Int) -> CGFloat {
            guard rowCardCount > 1 else { return 0 }
            let visibleStep = (width - cardWidth) / CGFloat(rowCardCount - 1)
            return min(3, max(rowCount == 1 ? -24 : -18, visibleStep - cardWidth))
        }

        if rowCount == 1 {
            let y = max(0, height - cardHeight)
            return HandLayout(
                width: width,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                rows: [
                    HandRowLayout(
                        startIndex: 0,
                        count: count,
                        y: y,
                        spacing: spacing(for: count)
                    )
                ]
            )
        }

        let lowerY = max(0, height - cardHeight)
        let rowStep = min(cardHeight + 4, max(cardHeight * 0.56, lowerY))
        let upperY = max(0, lowerY - rowStep)
        return HandLayout(
            width: width,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            rows: [
                HandRowLayout(
                    startIndex: 0,
                    count: firstRowCount,
                    y: upperY,
                    spacing: spacing(for: firstRowCount)
                ),
                HandRowLayout(
                    startIndex: firstRowCount,
                    count: secondRowCount,
                    y: lowerY,
                    spacing: spacing(for: secondRowCount)
                )
            ].filter { $0.count > 0 }
        )
    }

    private func handleGestureChange(
        _ value: DragGesture.Value,
        layout: HandLayout
    ) {
        if gestureStart == nil {
            gestureStart = value.startLocation
        }

        let horizontalDistance = abs(value.location.x - value.startLocation.x)
        let verticalDistance = abs(value.location.y - value.startLocation.y)
        if !isSwipeSelecting, horizontalDistance > 10 || verticalDistance > 10 {
            isSwipeSelecting = true
            if let startIndex = cardIndex(at: value.startLocation, layout: layout) {
                flipRange(endingAt: startIndex)
            }
        }

        guard isSwipeSelecting,
              let index = cardIndex(at: value.location, layout: layout)
        else { return }
        guard lastSwipeIndex != index || swipeFlippedIDs.isEmpty else { return }

        flipRange(endingAt: index)
    }

    private func handleGestureEnd(
        _ value: DragGesture.Value,
        layout: HandLayout
    ) {
        defer {
            gestureStart = nil
            isSwipeSelecting = false
            swipeFlippedIDs.removeAll()
            lastSwipeIndex = nil
        }

        guard !isSwipeSelecting,
              let card = card(at: value.location, layout: layout)
        else { return }

        onTap(card)
    }

    private func card(
        at location: CGPoint,
        layout: HandLayout
    ) -> Card? {
        guard let index = cardIndex(at: location, layout: layout) else { return nil }
        return cards[index]
    }

    private func cardIndex(
        at location: CGPoint,
        layout: HandLayout
    ) -> Int? {
        guard !cards.isEmpty, !layout.rows.isEmpty else { return nil }

        let row = layout.rows
            .filter { location.y >= $0.y - 16 && location.y <= $0.y + layout.cardHeight + 16 }
            .min { first, second in
                abs(location.y - (first.y + layout.cardHeight / 2)) < abs(location.y - (second.y + layout.cardHeight / 2))
            } ?? layout.rows.min { first, second in
                abs(location.y - (first.y + layout.cardHeight / 2)) < abs(location.y - (second.y + layout.cardHeight / 2))
            }

        guard let row, row.count > 0 else { return nil }
        let step = max(1, layout.cardWidth + row.spacing)
        let totalWidth = layout.cardWidth + CGFloat(max(0, row.count - 1)) * step
        let leftInset = max(0, (layout.width - totalWidth) / 2)
        let centerRelativeX = location.x - leftInset - layout.cardWidth / 2
        let rowIndex = min(row.count - 1, max(0, Int((centerRelativeX / step).rounded())))
        return min(cards.count - 1, row.startIndex + rowIndex)
    }

    private func flipRange(endingAt index: Int) {
        let start = lastSwipeIndex ?? index
        let lower = min(start, index)
        let upper = max(start, index)
        var cardsToFlip: [Card] = []

        for cardIndex in lower...upper {
            let card = cards[cardIndex]
            guard !swipeFlippedIDs.contains(card.id) else { continue }
            swipeFlippedIDs.insert(card.id)
            cardsToFlip.append(card)
        }

        if !cardsToFlip.isEmpty {
            onFlipCards(cardsToFlip)
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
