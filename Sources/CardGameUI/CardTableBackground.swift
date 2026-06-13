import SwiftUI

struct CardTableBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.28, blue: 0.20),
                    Color(red: 0.05, green: 0.10, blue: 0.18),
                    Color(red: 0.21, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            TableClothPattern()
                .stroke(.white.opacity(0.035), lineWidth: 1)
            LinearGradient(
                colors: [.black.opacity(0.32), .clear, .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct TableCenterSurface: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.12))
                .frame(width: width * 0.98, height: height * 0.82)
                .offset(y: 10)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.02, green: 0.36, blue: 0.23).opacity(0.58),
                            Color(red: 0.02, green: 0.20, blue: 0.19).opacity(0.36),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.55
                    )
                )
                .frame(width: width * 0.94, height: height * 0.76)
            LinearGradient(
                colors: [
                    .white.opacity(0.08),
                    .clear,
                    Color(red: 0.90, green: 0.08, blue: 0.08).opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask {
                Ellipse()
                    .frame(width: width * 0.90, height: height * 0.70)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

private struct TableClothPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 30

        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY - rect.width
        while y < rect.maxY + rect.width {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y + rect.width))
            y += spacing
        }

        return path
    }
}
