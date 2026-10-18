import SwiftUI

/// Circular ring of budget used. A full ring means the budget is used up.
struct BudgetRing<Center: View>: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 18
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
                .padding(lineWidth * 1.5)
        }
        .padding(lineWidth / 2)
    }
}

extension BudgetRing where Center == EmptyView {
    init(progress: Double, tint: Color, lineWidth: CGFloat = 18) {
        self.init(progress: progress, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}
