import AppKit
import ApplicationServices
import Foundation

/// Puts text into whatever field currently has keyboard focus.
///
/// Two strategies, in order:
/// 1. **Accessibility** — set `kAXSelectedTextAttribute` on the focused element. Clean and
///    instant, and it leaves the pasteboard untouched.
/// 2. **Pasteboard + ⌘V** — works in Electron apps and anything else with a half-hearted
///    AX implementation. The previous pasteboard contents are restored afterwards.
///
/// The catch that makes this non-obvious: **many apps return `.success` from the AX write
/// and then do nothing.** Electron (Cursor, VS Code, Slack, Discord), Chrome, and most
/// terminal emulators all report `kAXSelectedTextAttribute` as settable, accept the write,
/// and silently drop it. So the return value is not evidence of anything — strategy 1 is
/// only trusted when the insertion point can be *observed* to have moved.
///
/// This all works because the HUD is a non-activating panel: focus never leaves the user's
/// target app, so "the focused element" is still their text field.
@MainActor
enum TextInjector {
    enum Outcome: Equatable, Sendable {
        case inserted
        case unverified
        case failed(String)
    }

    struct Target {
        let pid: pid_t?
        let element: AXUIElement?

        @MainActor func isFocused() -> Bool {
            guard let pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                return false
            }
            guard let element else { return true }
            guard let current = TextInjector.focusedElement() else { return false }
            return CFEqual(element, current)
        }
    }

    static func captureTarget() -> Target {
        Target(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier, element: focusedElement())
    }

    private static func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(focused as AnyObject, to: AXUIElement.self)
    }

    static func insert(_ text: String, into target: Target) async -> Outcome {
        guard !text.isEmpty else { return .failed("La trascrizione è vuota.") }
        guard !Task.isCancelled, target.isFocused() else {
            return .failed("Il campo di destinazione è cambiato. Puoi copiare la dettatura dal menu.")
        }

        if let element = target.element, let before = selectedRange(of: element) {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
               settable.boolValue,
               AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                // Allow asynchronous AX implementations to settle before considering paste.
                for _ in 0..<4 {
                    guard target.isFocused() else { return .unverified }
                    guard let after = selectedRange(of: element) else { return .unverified }
                    if moved(before, after) { return .inserted }
                    do { try await Task.sleep(for: .milliseconds(25)) }
                    catch { return .unverified }
                }
            }
        }
        return await insertViaPasteboard(text, into: target)
    }

    private static func moved(_ before: CFRange, _ after: CFRange) -> Bool {
        before.location != after.location || before.length != after.length
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let value else { return nil }

        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    // MARK: - Strategy 2: Pasteboard + ⌘V

    private static func insertViaPasteboard(_ text: String, into target: Target) async -> Outcome {
        guard !Task.isCancelled, target.isFocused() else {
            return .failed("Inserimento annullato: il campo attivo è cambiato.")
        }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { copy[type] = data } }
            return copy
        }
        pasteboard.clearContents()
        let written = pasteboard.setString(text, forType: .string)
        let injectedChangeCount = pasteboard.changeCount
        defer { restore(saved, to: pasteboard, ifUnchangedSince: injectedChangeCount) }
        guard written else { return .failed("Impossibile preparare gli appunti.") }
        do { try await Task.sleep(for: .milliseconds(40)) }
        catch { return .failed("Inserimento annullato.") }
        guard pasteboard.changeCount == injectedChangeCount else {
            return .failed("Gli appunti sono cambiati. Dettatura disponibile nel menu.")
        }
        guard target.isFocused() else { return .failed("Il campo attivo è cambiato.") }
        let before = target.element.flatMap { selectedRange(of: $0) }
        guard postCommandV() else { return .failed("Impossibile inviare il comando Incolla.") }
        // A posted keystroke is not a delivery receipt. Observe the caret when available.
        for _ in 0..<20 {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return .unverified }
            guard target.isFocused() else { return .unverified }
            if let element = target.element, let before, let after = selectedRange(of: element),
               moved(before, after) { return .inserted }
        }
        return .unverified
    }

    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        let vKey: CGKeyCode = 9 // kVK_ANSI_V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }

        // Set explicitly rather than inheriting live hardware modifier state — the user may
        // still be resting a finger on something.
        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]]?,
        to pasteboard: NSPasteboard,
        ifUnchangedSince injectedChangeCount: Int
    ) {
        // Non sovrascrivere qualcosa che l'utente ha copiato durante l'incollaggio.
        guard pasteboard.changeCount == injectedChangeCount else {
            Log.inject.info("pasteboard changed by user — restore skipped")
            return
        }

        pasteboard.clearContents()
        guard let saved, !saved.isEmpty else { return }
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
