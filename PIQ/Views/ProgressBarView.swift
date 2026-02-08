import SwiftUI

struct ProgressBarView: View {
    let value: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(barColor)
                        .frame(width: barWidth(in: geometry.size.width), height: 6)
                }
            }
            .frame(height: 6)

            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var clampedValue: Int {
        min(max(value, 0), 100)
    }

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        totalWidth * CGFloat(clampedValue) / 100.0
    }

    private var barColor: Color {
        switch clampedValue {
        case 100:
            .green
        case 50...:
            .blue
        default:
            .orange
        }
    }

    private var label: String {
        "\(clampedValue)%"
    }
}
