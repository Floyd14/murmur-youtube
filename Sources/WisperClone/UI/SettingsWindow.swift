import AppKit
import ServiceManagement
import SwiftUI

struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @AppStorage(PreferenceKeys.onboardingCompleted) private var onboardingCompleted = false
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasMicrophone = Permissions.hasMicrophone
    @State private var loginItem = LoginItemManager.shared

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.wide) {
                    WisperCloneWordmark()

                    panel(label: "PUSH-TO-TALK") {
                        HStack(spacing: DS.Space.snug) {
                            ForEach(PushToTalkKey.allCases, id: \.self) { key in
                                selectionKey(key.displayName, selected: settings.pushToTalkKey == key) {
                                    settings.pushToTalkKey = key
                                    controller.reloadHotkey()
                                }
                            }
                        }
                        note("Tieni premuto il tasto scelto in qualsiasi applicazione per dettare.")
                    }

                    panel(label: "LINGUA") {
                        HStack(spacing: DS.Space.snug) {
                            ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                                selectionKey(
                                    language.displayName,
                                    selected: settings.recognitionLanguage == language
                                ) {
                                    settings.recognitionLanguage = language
                                }
                            }
                        }
                        note("Italiano è il valore predefinito. Automatico usa la lingua principale del Mac.")
                    }

                    panel(label: "COMPORTAMENTO") {
                        settingToggle("Pulisci esitazioni e punteggiatura", isOn: $settings.cleanupEnabled)
                        settingToggle("Pulizia intelligente sul dispositivo", isOn: $settings.smartCleanup)
                            .disabled(!FoundationModelFormatter.isAvailable || !settings.cleanupEnabled)
                        settingToggle("Suoni di avvio e completamento", isOn: $settings.soundEnabled)

                        if let reason = FoundationModelFormatter.unavailableReason {
                            note(reason)
                        } else {
                            note("Apple Intelligence migliora il testo senza inviarlo a servizi esterni.")
                        }
                    }

                    panel(label: "AVVIO") {
                        HStack {
                            settingToggle("Avvia WisperClone all'accesso", isOn: loginItemBinding)
                                .disabled(loginItem.status == .notFound)
                            Spacer()
                            Silkscreen(text: loginItemStatusLabel, color: DS.Color.inkSecondary)
                        }

                        note(loginItemStatusDescription)

                        if loginItem.status == .requiresApproval {
                            TransportKey(title: "Apri Impostazioni di Sistema") {
                                openLoginItemsSettings()
                            }
                        }

                        if let error = loginItem.error {
                            Text("Impossibile modificare l'avvio automatico: \(error)")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    panel(label: "PRIVACY E PERMESSI") {
                        permissionLine("Accessibilità", granted: hasAccessibility) {
                            Permissions.promptForAccessibility()
                            if !Permissions.hasAccessibility { Permissions.openAccessibilitySettings() }
                        }
                        permissionLine("Microfono", granted: hasMicrophone) {
                            Task { @MainActor in
                                hasMicrophone = await Permissions.requestMicrophone()
                                if !hasMicrophone { Permissions.openMicrophoneSettings() }
                            }
                        }
                        note("Audio e trascrizioni non vengono salvati. Il dizionario personale resta sul Mac.")
                    }

                    HStack {
                        Button("Ripeti introduzione") {
                            onboardingCompleted = false
                        }
                        .buttonStyle(.plain)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.64))

                        Spacer()

                        Silkscreen(text: versionLabel, color: DS.Color.inkOnDeck.opacity(0.64))
                    }
                }
                .padding(DS.Space.panel)
            }
        }
        .frame(width: 620, height: 700)
        .task {
            while !Task.isCancelled {
                hasAccessibility = Permissions.hasAccessibility
                hasMicrophone = Permissions.hasMicrophone
                loginItem.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "WISPER CLONE \(version ?? "—") · LOCALE"
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: {
                loginItem.status == .enabled || loginItem.status == .requiresApproval
            },
            set: { loginItem.setEnabled($0) }
        )
    }

    private var loginItemStatusLabel: String {
        switch loginItem.status {
        case .enabled:
            "ATTIVO"
        case .requiresApproval:
            "RICHIEDE APPROVAZIONE"
        case .notRegistered:
            "DISATTIVO"
        case .notFound:
            "NON DISPONIBILE"
        @unknown default:
            "STATO SCONOSCIUTO"
        }
    }

    private var loginItemStatusDescription: String {
        switch loginItem.status {
        case .enabled:
            "WisperClone si aprirà automaticamente ai prossimi accessi al Mac."
        case .requiresApproval:
            "La registrazione esiste, ma macOS richiede la tua approvazione in Generali > Elementi login ed estensioni."
        case .notRegistered:
            "WisperClone non è registrato tra gli elementi che si aprono all'accesso."
        case .notFound:
            "macOS non trova il servizio dell'app. Installa e avvia la versione firmata da Applicazioni."
        @unknown default:
            "macOS ha restituito uno stato dell'elemento di login non riconosciuto."
        }
    }

    private func openLoginItemsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    private func panel<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Silkscreen(text: label, large: true)
            content()
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrushedPanel())
    }

    private func selectionKey(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        TransportKey(title: title, isEngaged: selected, engagedColor: DS.Color.ink, action: action)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .fill(DS.Color.selection)
                }
            }
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Silkscreen(text: title) }
            .toggleStyle(.switch)
    }

    private func permissionLine(
        _ title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DS.Space.snug) {
            Lamp(color: DS.Color.meterGreen, isLit: granted)
            Text(title)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
            Spacer()
            if granted {
                Silkscreen(text: "CONCESSO", color: DS.Color.inkSecondary)
            } else {
                TransportKey(title: "Concedi", action: action)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
