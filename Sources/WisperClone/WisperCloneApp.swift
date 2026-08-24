import AppKit
import SwiftUI

@main
struct WisperCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Detto", id: "main") {
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
        hud = HUDPanel(controller: controller)

        if !controller.activate() {
            retryActivation()
        }

        observeState()
        Log.app.info("Detto pronto — tieni premuto \(Settings.shared.pushToTalkKey.displayName)")
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
            controller.activate()
            Log.app.info("Accessibilità concessa — scorciatoia attiva")
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("DETTO")
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

        Button("Apri Detto") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        if !Permissions.hasAccessibility {
            Button("Concedi Accessibilità…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Concedi Microfono…") { Permissions.openMicrophoneSettings() }
        }

        Button("Esci da Detto") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
