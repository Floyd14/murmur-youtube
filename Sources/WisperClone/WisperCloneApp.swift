import AppKit
import SwiftUI

@main
struct WisperCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("WisperClone", id: "main") {
            MainWindow(controller: delegate.controller)
        }
        .defaultSize(width: 780, height: 560)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }

        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        _ = DictionaryStore.shared
        hud = HUDPanel(controller: controller)

        if !controller.activate() {
            Permissions.promptForAccessibility()
            retryActivation()
        }

        observeState()
        Log.app.info("WisperClone pronto — tieni premuto \(Settings.shared.pushToTalkKey.displayName)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
    }

    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }

            for attempt in 1...5 {
                if controller.activate() {
                    Log.app.info("Accessibilità concessa — scorciatoia attiva")
                    return
                }
                Log.hotkey.error("attivazione scorciatoia fallita — tentativo \(attempt, privacy: .public)/5")
                try? await Task.sleep(for: .seconds(1))
            }
            Log.hotkey.fault("impossibile attivare la scorciatoia dopo 5 tentativi")
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("WISPER CLONE")
        Text("Tieni premuto \(settings.pushToTalkKey.displayName) per dettare")

        Divider()

        Picker("Lingua", selection: $settings.recognitionLanguage) {
            ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                Text(language.displayName).tag(language)
            }
        }

        Toggle("Pulisci la trascrizione", isOn: $settings.cleanupEnabled)
        if settings.cleanupEnabled {
            Toggle("Pulizia intelligente locale", isOn: $settings.smartCleanup)
                .disabled(!FoundationModelFormatter.isAvailable)
        }
        Toggle("Suoni", isOn: $settings.soundEnabled)

        Divider()

        Button("Apri WisperClone") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        if !Permissions.hasAccessibility {
            Button("Concedi Accessibilità…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Concedi Microfono…") { Permissions.openMicrophoneSettings() }
        }

        Button("Esci da WisperClone") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
