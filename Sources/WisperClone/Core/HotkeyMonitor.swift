import AppKit
import Carbon.HIToolbox
import Foundation

/// Which modifier key holds the mic open.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so `onRelease` never fires. The mic
    /// stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .fn: .maskSecondaryFn                        // no left/right variant exists
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .fn: "fn"
        case .rightCommand: "Right ⌘"
        }
    }

}

/// Watches for a held modifier key using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var releaseRecoveryTask: Task<Void, Never>?
    private var isPressed = false

    var key: PushToTalkKey = .rightOption
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // Passive observation is a safety boundary: WisperClone can never suppress or
            // delay Shift, Command, Option, fn, or any other system keyboard event.
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.key.displayName)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        releaseRecoveryTask?.cancel()
        releaseRecoveryTask = nil
        isPressed = false
    }

    // MARK: - Tap callback

    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) {
        // If macOS disables the tap while the key is held, its release can be lost. End the
        // session before re-arming so the microphone and HUD can never remain latched on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            forceReleaseIfNeeded(reason: "event tap disabilitato")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        guard type == .flagsChanged, keyCode == key.keyCode else { return }

        let nowPressed = flags.contains(key.flag)
        guard nowPressed != isPressed else { return }
        isPressed = nowPressed

        if nowPressed {
            onPress?()
            startReleaseRecovery()
        } else {
            releaseRecoveryTask?.cancel()
            releaseRecoveryTask = nil
            onRelease?()
        }
    }

    /// Polls physical state only while the hotkey is held. This is a fallback for a dropped
    /// `flagsChanged` release; it does not generate or consume keyboard events.
    private func startReleaseRecovery() {
        releaseRecoveryTask?.cancel()
        releaseRecoveryTask = Task { @MainActor [weak self] in
            while let self, self.isPressed {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }

                let stillDown = CGEventSource.keyState(
                    .combinedSessionState,
                    key: CGKeyCode(self.key.keyCode)
                )
                if !stillDown {
                    self.forceReleaseIfNeeded(reason: "rilascio hotkey recuperato")
                    return
                }
            }
        }
    }

    private func forceReleaseIfNeeded(reason: String) {
        releaseRecoveryTask?.cancel()
        releaseRecoveryTask = nil
        guard isPressed else { return }

        isPressed = false
        Log.hotkey.error("\(reason, privacy: .public)")
        onRelease?()
    }
}
