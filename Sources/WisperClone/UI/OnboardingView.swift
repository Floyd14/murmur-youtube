import SwiftUI

struct OnboardingView: View {
    @Bindable var controller: DictationController
    let onComplete: () -> Void

    @State private var step = 0
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasMicrophone = Permissions.hasMicrophone
    @State private var settings = Settings.shared

    private let stepCount = 3

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            VStack(spacing: DS.Space.wide) {
                HStack {
                    WisperCloneWordmark()
                    Spacer()
                    stepIndicator
                }

                ZStack {
                    BrushedPanel()
                    Group {
                        switch step {
                        case 0: welcomeStep
                        case 1: permissionsStep
                        default: readyStep
                        }
                    }
                    .padding(DS.Space.panel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                navigation
            }
            .padding(DS.Space.panel)
        }
        .frame(minWidth: 720, minHeight: 520)
        .task {
            while !Task.isCancelled {
                hasAccessibility = Permissions.hasAccessibility
                hasMicrophone = Permissions.hasMicrophone
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: DS.Space.tight) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? DS.Color.inkOnDeck : DS.Color.inkOnDeck.opacity(0.24))
                    .frame(width: index == step ? 28 : 10, height: 4)
                    .animation(DS.Motion.panel, value: step)
            }
        }
        .accessibilityLabel("Passaggio \(step + 1) di \(stepCount)")
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            Silkscreen(text: "BENVENUTO", large: true)
            Text("La voce diventa testo.\nSenza lasciare il tuo Mac.")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tieni premuto un tasto, parla e rilascialo. WisperClone trascrive in italiano e inserisce il risultato direttamente nell'app che stai usando.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkSecondary)
                .frame(maxWidth: 520, alignment: .leading)

            HStack(spacing: DS.Space.roomy) {
                feature("lock.shield", "Locale", "Audio e testo restano sul dispositivo")
                feature("waveform", "Immediato", "Trascrizione mentre parli")
                feature("text.cursor", "Universale", "Funziona nei campi di testo del Mac")
            }

            Spacer()
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            Silkscreen(text: "AUTORIZZAZIONI", large: true)
            Text("Due permessi, entrambi necessari.")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Color.ink)

            permissionRow(
                title: "Accessibilità",
                detail: "Rileva il push-to-talk e inserisce il testo nell'app attiva.",
                granted: hasAccessibility,
                actionTitle: "Concedi accesso"
            ) {
                Permissions.promptForAccessibility()
                if !Permissions.hasAccessibility {
                    Permissions.openAccessibilitySettings()
                }
            }

            permissionRow(
                title: "Microfono",
                detail: "Ascolta soltanto mentre registri; l'audio non viene salvato.",
                granted: hasMicrophone,
                actionTitle: "Concedi accesso"
            ) {
                Task { @MainActor in
                    hasMicrophone = await Permissions.requestMicrophone()
                    if !hasMicrophone { Permissions.openMicrophoneSettings() }
                }
            }

            Text("WisperClone non richiede account, API key o servizi cloud.")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)

            Spacer()
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            Silkscreen(text: "PUSH-TO-TALK", large: true)
            Text("Scegli il tasto più naturale.")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Color.ink)

            HStack(spacing: DS.Space.snug) {
                ForEach(PushToTalkKey.allCases, id: \.self) { key in
                    TransportKey(
                        title: key.displayName,
                        isEngaged: settings.pushToTalkKey == key,
                        engagedColor: DS.Color.ink
                    ) {
                        settings.pushToTalkKey = key
                        controller.reloadHotkey()
                    }
                    .background {
                        if settings.pushToTalkKey == key {
                            RoundedRectangle(cornerRadius: DS.Radius.control)
                                .fill(DS.Color.selection)
                        }
                    }
                }
            }

            DeckWindow {
                HStack(spacing: DS.Space.base) {
                    Lamp(color: DS.Color.meterGreen, isLit: true)
                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Text("Tieni premuto \(settings.pushToTalkKey.displayName)")
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                        Text("Parla in italiano, poi rilascia per inserire il testo.")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Color.inkOnDeck.opacity(0.62))
                    }
                    Spacer()
                }
                .padding(DS.Space.roomy)
            }

            Text("Potrai cambiare lingua, tasto e pulizia in qualsiasi momento dalle Impostazioni.")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)

            Spacer()
        }
    }

    private var navigation: some View {
        HStack(spacing: DS.Space.snug) {
            if step > 0 {
                TransportKey(title: "Indietro") {
                    withAnimation(DS.Motion.panel) { step -= 1 }
                }
            }

            Spacer()

            if step < stepCount - 1 {
                TransportKey(
                    title: "Continua",
                    isEngaged: canContinue,
                    engagedColor: DS.Color.ink
                ) {
                    guard canContinue else { return }
                    withAnimation(DS.Motion.panel) { step += 1 }
                }
                .disabled(!canContinue)
            } else {
                TransportKey(title: "Inizia a dettare", isEngaged: true, engagedColor: DS.Color.ink) {
                    onComplete()
                }
            }
        }
    }

    private var canContinue: Bool {
        step != 1 || (hasAccessibility && hasMicrophone)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Color.ink)
            Silkscreen(text: title, large: true)
            Text(detail)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DS.Space.roomy) {
            Lamp(color: DS.Color.meterGreen, isLit: granted)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(title)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
                Text(detail)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.inkSecondary)
            }
            Spacer()
            if granted {
                Silkscreen(text: "CONCESSO", color: DS.Color.inkSecondary)
            } else {
                TransportKey(title: actionTitle, action: action)
            }
        }
        .padding(DS.Space.roomy)
        .background(DS.Color.selection.opacity(0.52), in: .rect(cornerRadius: DS.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel)
                .strokeBorder(DS.Color.selectionEdge, lineWidth: DS.Border.hairline)
        }
    }
}
