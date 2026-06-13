import SwiftUI

private enum GameRoute {
    case fourFourteen
    case douDizhu
    case runFast
    case guanDan
}

struct ContentView: View {
    @State private var selectedGame: GameRoute?

    var body: some View {
        Group {
            switch selectedGame {
            case .fourFourteen:
                FourFourteenTableView {
                    selectedGame = nil
                }
            case .douDizhu:
                DouDizhuTableView {
                    selectedGame = nil
                }
            case .runFast:
                RunFastTableView {
                    selectedGame = nil
                }
            case .guanDan:
                GuanDanTableView {
                    selectedGame = nil
                }
            case nil:
                GameSelectionView { route in
                    selectedGame = route
                }
            }
        }
    }
}

private struct GameSelectionView: View {
    let onSelect: (GameRoute) -> Void

    var body: some View {
        ZStack {
            CardTableBackground()
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Poker")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 7, y: 3)
                        Text("选择玩法")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.42), radius: 4, y: 2)
                        PlayedCardsFan(cards: sampleCards)
                            .frame(width: 190, height: 70)
                            .padding(.top, 6)
                    }
                    .frame(width: min(230, proxy.size.width * 0.28), alignment: .leading)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        gameButton(
                            title: "414",
                            subtitle: "4人单机 · 3个AI",
                            description: "红桃3先出，叉/勾抢牌权，炸弹、双王和4A4决定关键手。",
                            accent: .yellow,
                            enabled: true
                        ) {
                            onSelect(.fourFourteen)
                        }
                        gameButton(
                            title: "斗地主",
                            subtitle: "3人单机 · 2个AI",
                            description: "叫地主后1打2，顺子、飞机、炸弹/王炸，农民会协作拦地主。",
                            accent: Color(red: 1.00, green: 0.56, blue: 0.12),
                            enabled: true
                        ) {
                            onSelect(.douDizhu)
                        }
                        gameButton(
                            title: "跑得快",
                            subtitle: "3人单机 · 黑桃3",
                            description: "每人16张，黑桃3首出，目标尽快跑完，炸弹可压普通牌。",
                            accent: Color(red: 0.34, green: 0.76, blue: 1.00),
                            enabled: true
                        ) {
                            onSelect(.runFast)
                        }
                        gameButton(
                            title: "掼蛋",
                            subtitle: "4人2v2 · 两副牌",
                            description: "固定打2，红桃2逢人配，同花顺、多张炸和队友接风是核心。",
                            accent: Color(red: 1.00, green: 0.68, blue: 0.20),
                            enabled: true
                        ) {
                            onSelect(.guanDan)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, proxy.size.width > 760 ? 40 : 22)
                .padding(.vertical, 26)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func gameButton(
        title: String,
        subtitle: String,
        description: String,
        accent: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                Text(subtitle)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .foregroundStyle(.white.opacity(enabled ? 0.78 : 0.42))
                Text(description)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .foregroundStyle(.white.opacity(enabled ? 0.62 : 0.34))
                Rectangle()
                    .fill(enabled ? accent : .white.opacity(0.18))
                    .frame(height: enabled ? 3 : 1)
                    .padding(.top, 2)
            }
            .foregroundStyle(enabled ? accent : .white.opacity(0.40))
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .shadow(color: enabled ? accent.opacity(0.58) : .clear, radius: 7)
            .shadow(color: .black.opacity(0.46), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var sampleCards: [Card] {
        [
            Card(rank: .four, suit: .hearts, deckIndex: 0),
            Card(rank: .ace, suit: .spades, deckIndex: 0),
            Card(rank: .four, suit: .diamonds, deckIndex: 0),
            Card(rank: .smallJoker, suit: nil, deckIndex: 0),
            Card(rank: .bigJoker, suit: nil, deckIndex: 0)
        ]
    }
}
