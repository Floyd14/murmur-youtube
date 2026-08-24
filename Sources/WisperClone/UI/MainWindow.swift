import SwiftUI

struct MainWindow: View {
    @Bindable var controller: DictationController
    @AppStorage(PreferenceKeys.onboardingCompleted) private var onboardingCompleted = false
    @State private var section: Section = .dictation

    enum Section: String, CaseIterable, Identifiable {
        case dictation
        case dictionary

        var id: String { rawValue }
        var title: String { self == .dictation ? "Dettatura" : "Dizionario" }
    }

    var body: some View {
        Group {
            if onboardingCompleted {
                dashboard
            } else {
                OnboardingView(controller: controller) {
                    withAnimation(DS.Motion.panel) { onboardingCompleted = true }
                }
            }
        }
    }

    private var dashboard: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            VStack(spacing: DS.Space.base) {
                HStack {
                    WisperCloneWordmark(compact: true)
                    Spacer()
                    HStack(spacing: DS.Space.tight) {
                        Lamp(color: DS.Color.meterGreen, isLit: true)
                        Silkscreen(text: "SOLO SUL DISPOSITIVO", color: DS.Color.inkOnDeck.opacity(0.72))
                    }
                }
                .padding(.horizontal, DS.Space.tight)

                TransportPanel(controller: controller)
                sectionKeys

                Well {
                    Group {
                        switch section {
                        case .dictation: DictationOverview(controller: controller)
                        case .dictionary: DictionaryPanel()
                        }
                    }
                    .padding(DS.Space.hair)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(DS.Space.roomy)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var sectionKeys: some View {
        HStack(spacing: DS.Space.snug) {
            ForEach(Section.allCases) { candidate in
                TransportKey(
                    title: candidate.title,
                    isEngaged: section == candidate,
                    engagedColor: DS.Color.ink
                ) {
                    withAnimation(DS.Motion.panel) { section = candidate }
                }
                .background {
                    if section == candidate {
                        RoundedRectangle(cornerRadius: DS.Radius.control)
                            .fill(DS.Color.selection)
                    }
                }
            }
            Spacer()
            Vents(count: 8)
        }
    }
}

private struct TransportPanel: View {
    @Bindable var controller: DictationController
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRecording: Bool { controller.state.isActive }

    var body: some View {
        HStack(spacing: DS.Space.roomy) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Silkscreen(text: "Controlli")
                HStack(spacing: DS.Space.snug) {
                    TransportKey(
                        title: isRecording ? "Ferma" : "Registra",
                        systemImage: isRecording ? "stop.fill" : "circle.fill",
                        isEngaged: isRecording
                    ) {
                        if isRecording {
                            controller.stopButtonRecording()
                        } else {
                            controller.startButtonRecording()
                        }
                    }

                    HStack(spacing: DS.Space.tight) {
                        Lamp(color: DS.Color.record, isLit: isRecording)
                        Silkscreen(text: "REC")
                    }
                    .padding(.leading, DS.Space.tight)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Silkscreen(text: "Livello")
                VUMeter(level: controller.level, isActive: isRecording)
                    .frame(width: 168, height: 54)
            }

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Silkscreen(text: "Durata")
                DeckWindow {
                    Readout(text: counterText, large: true)
                        .padding(.horizontal, DS.Space.base)
                        .padding(.vertical, DS.Space.snug)
                }
            }

            Spacer()
            VStack(alignment: .trailing, spacing: DS.Space.snug) {
                Screw()
                Screw()
            }
        }
        .padding(DS.Space.roomy)
        .background(BrushedPanel())
        .onChange(of: controller.state.isActive) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var counterText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct DictationOverview: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            HStack(spacing: DS.Space.base) {
                Lamp(
                    color: controller.state.isActive ? DS.Color.record : DS.Color.meterGreen,
                    isLit: true
                )
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Silkscreen(text: statusTitle, large: true, color: DS.Color.inkOnDeck)
                    Text(statusDetail)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.72))
                }
            }

            Divider().overlay(DS.Color.seam)

            infoRow("Motore", value: "Apple Speech · sul dispositivo")
            infoRow("Lingua", value: settings.recognitionLanguage.displayName)
            infoRow("Privacy", value: "Audio e testo non vengono salvati")
            infoRow("Scorciatoia", value: "Tieni premuto \(settings.pushToTalkKey.displayName)")

            Spacer()

            Text("Concedi Microfono e Accessibilità quando richiesto. La trascrizione viene inserita direttamente nel campo di testo attivo.")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.deck)
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: "Pronto"
        case .starting: "Avvio…"
        case .listening: "In ascolto"
        case .finishing: "Trascrizione…"
        case .error: "Errore"
        }
    }

    private var statusDetail: String {
        switch controller.state {
        case .idle: "Premi Registra oppure usa la scorciatoia globale."
        case .starting: "Preparazione del microfono e del modello locale."
        case .listening: controller.transcript.isEmpty ? "Parla normalmente." : controller.transcript
        case .finishing: "Completamento e inserimento del testo."
        case .error(let message): message
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Silkscreen(text: label, color: DS.Color.inkOnDeck.opacity(0.55))
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkOnDeck)
            Spacer()
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkOnDeck)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(DS.Color.deck)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.seam).frame(height: DS.Border.seam)
        }
    }
}

struct EmptyPanel: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.snug) {
            Silkscreen(text: label, large: true, color: DS.Color.inkOnDeck.opacity(0.55))
            Text(detail)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
