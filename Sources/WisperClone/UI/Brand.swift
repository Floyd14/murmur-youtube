import SwiftUI

enum WisperCloneBrand {
    static let name = "WisperClone"
    static let wordmark = "WISPER CLONE"
    static let tagline = "Parla. È già scritto."

    enum Color {
        static let charcoal = SwiftUI.Color(red: 0.09, green: 0.085, blue: 0.075)
        static let paper = SwiftUI.Color(red: 0.88, green: 0.85, blue: 0.78)
        static let paperMuted = SwiftUI.Color(red: 0.61, green: 0.58, blue: 0.52)
        static let record = SwiftUI.Color(red: 0.78, green: 0.20, blue: 0.16)
    }
}

struct WisperCloneMark: View {
    var size: CGFloat = 44

    private let bars: [CGFloat] = [0.34, 0.62, 1.0, 0.62, 0.34]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(WisperCloneBrand.Color.charcoal)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(WisperCloneBrand.Color.paperMuted.opacity(0.42), lineWidth: 1)
                }

            HStack(alignment: .center, spacing: size * 0.055) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(WisperCloneBrand.Color.paper)
                        .frame(width: size * 0.07, height: size * 0.42 * height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Circle()
                .fill(WisperCloneBrand.Color.record)
                .frame(width: size * 0.12, height: size * 0.12)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WisperCloneWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: DS.Space.base) {
            WisperCloneMark(size: compact ? 34 : 46)

            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Text(WisperCloneBrand.wordmark)
                    .font(.custom("Helvetica Neue", size: compact ? 15 : 19).weight(.bold))
                    .tracking(compact ? 2.4 : 3.2)
                    .foregroundStyle(DS.Color.inkOnDeck)
                if !compact {
                    Text(WisperCloneBrand.tagline)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.64))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WisperCloneBrand.name). \(WisperCloneBrand.tagline)")
    }
}
