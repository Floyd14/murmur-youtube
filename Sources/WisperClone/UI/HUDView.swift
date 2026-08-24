import SwiftUI

private enum HUDBrand {
    static let accent = Color(red: 0.42, green: 0.55, blue: 1.0)
    static let accentWarm = Color(red: 0.76, green: 0.47, blue: 1.0)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentWarm],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct HUDView: View {
    @Bindable var controller: DictationController

    var body: some View {
        Waveform(
            level: controller.level,
            isActive: controller.state == .listening,
            style: isError
                ? AnyShapeStyle(Color.red.opacity(0.9))
                : AnyShapeStyle(HUDBrand.gradient)
        )
        .frame(width: 76, height: 26)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 108, height: 52)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatus)
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var accessibilityStatus: String {
        switch controller.state {
        case .starting: "Avvio dettatura"
        case .listening: "In ascolto"
        case .finishing: "Trascrizione"
        case .error: "Errore di dettatura"
        case .idle: ""
        }
    }
}

private struct Waveform: View {
    let level: Float
    let isActive: Bool
    let style: AnyShapeStyle

    private static let barCount = 12
    private static let phases: [Double] = (0..<barCount).map { index in
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(style)
                        .frame(width: 3, height: height(for: index, at: time))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floorHeight: CGFloat = 3
        guard isActive else { return floorHeight }

        let phase = Self.phases[index]
        let wave = sin(time * 6.0 + phase * .pi * 2)
        let amplitude = CGFloat(max(0.04, level))
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floorHeight + max(0, scaled) * 23
    }
}
