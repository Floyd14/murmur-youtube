import SwiftUI

struct HUDView: View {
    @Bindable var controller: DictationController

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Circle()
                .fill(controller.state.isActive ? WisperCloneBrand.Color.record : WisperCloneBrand.Color.paperMuted)
                .frame(width: 7, height: 7)

            Waveform(level: controller.level, isActive: controller.state == .listening)
                .frame(width: 72, height: 26)

            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isError ? WisperCloneBrand.Color.record : WisperCloneBrand.Color.paper)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: controller.transcript)
        }
        .padding(.horizontal, DS.Space.roomy)
        .padding(.vertical, DS.Space.base)
        .frame(width: 340, height: 72)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WisperCloneBrand.Color.charcoal.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WisperCloneBrand.Color.paperMuted.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.32), radius: 16, y: 7)
        }
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var label: String {
        switch controller.state {
        case .starting: "Avvio…"
        case .listening: controller.transcript.isEmpty ? "In ascolto…" : controller.transcript
        case .finishing: controller.transcript.isEmpty ? "Trascrizione…" : controller.transcript
        case .error(let message): message
        case .idle: ""
        }
    }
}

private struct Waveform: View {
    let level: Float
    let isActive: Bool

    private static let barCount = 11
    private static let phases: [Double] = (0..<barCount).map { index in
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(WisperCloneBrand.Color.paper)
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
