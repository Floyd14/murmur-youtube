import SwiftUI

struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.wide) {
                panel(label: "Pulsante push-to-talk") {
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
                    note("Tieni premuto questo tasto in qualsiasi applicazione per dettare.")
                }

                panel(label: "Lingua") {
                    HStack(spacing: DS.Space.snug) {
                        ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                            TransportKey(
                                title: language.displayName,
                                isEngaged: settings.recognitionLanguage == language,
                                engagedColor: DS.Color.ink
                            ) {
                                settings.recognitionLanguage = language
                            }
                            .background {
                                if settings.recognitionLanguage == language {
                                    RoundedRectangle(cornerRadius: DS.Radius.control)
                                        .fill(DS.Color.selection)
                                }
                            }
                        }
                    }
                    note("Italiano è il valore predefinito. Automatico usa la lingua principale del Mac.")
                }

                panel(label: "Pulizia") {
                    Toggle(isOn: $settings.cleanupEnabled) {
                        Silkscreen(text: "Pulisci le trascrizioni")
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $settings.smartCleanup) {
                        Silkscreen(text: "Usa Apple Intelligence sul dispositivo")
                    }
                    .toggleStyle(.switch)
                    .disabled(!FoundationModelFormatter.isAvailable || !settings.cleanupEnabled)

                    if let reason = FoundationModelFormatter.unavailableReason {
                        note(reason)
                    } else {
                        note("Rimuove esitazioni e sistema punteggiatura senza inviare il testo a servizi esterni.")
                    }
                }

                Spacer()
            }
            .padding(DS.Space.panel)
        }
        .frame(width: 560, height: 560)
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
