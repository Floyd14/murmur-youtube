import WisperDictionary
import Foundation
import Observation

/// The dictionary, persisted as a plain text file you can edit by hand.
///
/// A text file rather than JSON, because the spec asks for something editable outside the UI
/// and JSON is only nominally that — quoting, escaping and a trailing-comma trap for anyone
/// adding a line in a hurry. The format is one entry per line:
///
/// ```
/// WisperClone
/// Monte Bianco
/// uisper clon -> WisperClone
/// # off: esempio errato -> Esempio corretto
/// ```
///
/// A bare line is a term. `X -> Y` is a correction. `#` starts a comment, and a disabled
/// entry is written as a `# off:` comment so it survives a round trip through the file
/// without silently disappearing.
///
/// The file is watched, so editing it in a text editor updates the UI live and vice versa.
@MainActor
@Observable
final class DictionaryStore {
    static let shared = DictionaryStore(
        fileURL: fileURL,
        installStarterDictionary: true,
        watchChanges: true
    )

    private(set) var entries: [DictionaryEntry] = []

    /// A persistence failure stays visible until the failed operation succeeds or the user
    /// dismisses it. In particular, a failed save must not look successful in the editor.
    private(set) var persistenceError: String?

    /// Bumped whenever entries change, so the engine can rebuild its bias list lazily
    /// instead of on every transcription.
    private(set) var revision = 0

    let dictionaryURL: URL

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var lastKnownFileContents: String?
    private var persistenceErrorOperation: PersistenceOperation?

    private enum PersistenceOperation {
        case read
        case write
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WisperClone", isDirectory: true)
            .appendingPathComponent("dictionary.txt")
    }

    /// The injectable URL keeps persistence and file-watching behavior testable without
    /// touching the user's real dictionary.
    init(
        fileURL: URL = DictionaryStore.fileURL,
        installStarterDictionary: Bool = true,
        watchChanges: Bool = true
    ) {
        dictionaryURL = fileURL

        if installStarterDictionary {
            do {
                try Self.installStarterDictionaryIfNeeded(at: fileURL)
            } catch {
                report(error, operation: .write, action: "creare")
            }
        }

        reloadFromDisk()
        if watchChanges { startWatching() }
    }

    // MARK: - Editing

    @discardableResult
    func add(_ entry: DictionaryEntry) -> Bool {
        commit(entries + [entry])
    }

    @discardableResult
    func update(_ entry: DictionaryEntry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            persistenceError = "La voce non è più presente nel dizionario. Riapri l’editor e riprova."
            persistenceErrorOperation = .write
            return false
        }
        var updatedEntries = entries
        updatedEntries[index] = entry
        return commit(updatedEntries)
    }

    @discardableResult
    func delete(_ entry: DictionaryEntry) -> Bool {
        commit(entries.filter { $0.id != entry.id })
    }

    @discardableResult
    func delete(ids: Set<UUID>) -> Bool {
        commit(entries.filter { !ids.contains($0.id) })
    }

    func clearPersistenceError() {
        persistenceError = nil
        persistenceErrorOperation = nil
    }

    /// Case- and diacritic-insensitive search across both sides of an entry.
    func filtered(by query: String) -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.write.localizedStandardContains(trimmed) || $0.hear.localizedStandardContains(trimmed)
        }
    }

    /// A corrector over the current entries. Rebuilt on demand — compiling a few dozen small
    /// regexes is cheap next to transcription, and caching it invites staleness.
    var corrector: DictionaryCorrector { DictionaryCorrector(entries: entries) }

    var biasPhrases: [String] { DictionaryCorrector.biasPhrases(from: entries) }

    // MARK: - Persistence

    private static func installStarterDictionaryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let text = header + starterEntries + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reloads a hand-edited file. A missing, temporarily replaced, or unreadable file never
    /// destroys the last valid in-memory dictionary: editors commonly implement saves as a
    /// delete/rename sequence and the watcher can observe the gap between those operations.
    func reloadFromDisk() {
        let text: String
        do {
            text = try String(contentsOf: dictionaryURL, encoding: .utf8)
        } catch {
            report(error, operation: .read, action: "leggere")
            return
        }

        if persistenceErrorOperation == .read {
            clearPersistenceError()
        }
        guard text != lastKnownFileContents else { return }

        entries = Self.parse(text)
        lastKnownFileContents = text
        revision += 1
    }

    private func commit(_ candidateEntries: [DictionaryEntry]) -> Bool {
        let text = Self.serialize(candidateEntries)
        do {
            try FileManager.default.createDirectory(
                at: dictionaryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: dictionaryURL, atomically: true, encoding: .utf8)
        } catch {
            report(error, operation: .write, action: "salvare")
            return false
        }

        entries = candidateEntries
        lastKnownFileContents = text
        revision += 1
        clearPersistenceError()
        return true
    }

    static func parse(_ text: String) -> [DictionaryEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }

            // `# off:` is a disabled entry; any other comment is just a comment.
            var isEnabled = true
            if line.hasPrefix("#") {
                let stripped = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard stripped.lowercased().hasPrefix("off:") else { return nil }
                line = stripped.dropFirst(4).trimmingCharacters(in: .whitespaces)
                isEnabled = false
                guard !line.isEmpty else { return nil }
            }

            if let arrow = line.range(of: "->") {
                let hear = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let write = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !hear.isEmpty, !write.isEmpty else { return nil }
                return DictionaryEntry(kind: .correction, write: write, hear: hear, isEnabled: isEnabled)
            }

            return DictionaryEntry(kind: .term, write: line, isEnabled: isEnabled)
        }
    }

    private static func serialize(_ entries: [DictionaryEntry]) -> String {
        let body = entries.map(\.fileLine).joined(separator: "\n")
        return header + body + "\n"
    }

    private func report(_ error: Error, operation: PersistenceOperation, action: String) {
        // A later watcher read must not hide a failed user-initiated save.
        guard persistenceErrorOperation != .write || operation == .write else { return }
        persistenceError = "Impossibile \(action) dictionary.txt: \(error.localizedDescription)"
        persistenceErrorOperation = operation
    }

    private static let header = """
        # Dizionario WisperClone
        #
        #   WisperClone                         termine da riconoscere
        #   uisper clon -> WisperClone          correzione automatica
        #   # off: regola errata -> Testo giusto   voce disattivata
        #
        # Puoi modificare direttamente questo file; l'app rileva le modifiche.

        """

    private static let starterEntries = """
        # Termini italiani e tecnici iniziali
        WisperClone
        macOS
        MacBook
        iPhone
        iPad
        ChatGPT
        OpenAI
        Claude
        Claude Code
        GitHub
        Xcode
        Swift
        SwiftUI

        # Correzioni iniziali ad alta affidabilità
        uisper clon -> WisperClone
        whisper clone -> WisperClone
        chat g p t -> ChatGPT
        """

    // MARK: - External edits

    /// Watches the containing directory rather than the dictionary inode. Atomic saves replace
    /// that inode, while the directory remains stable across file deletion and recreation. A
    /// second watcher follows the current file inode so direct, non-atomic edits are detected.
    private func startWatching() {
        directoryWatcher?.cancel()

        let directoryURL = dictionaryURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            report(error, operation: .read, action: "monitorare")
            return
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            report(error, operation: .read, action: "monitorare")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.reloadFromDisk()
            // A directory event may mean the file inode was replaced. Rearm explicitly after
            // reading the new file; cancellation itself cannot recursively trigger this path.
            self.armFileWatcher()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        directoryWatcher = source
        armFileWatcher()
    }

    /// Follows the current dictionary inode to catch editors that modify it in place. File
    /// replacement is handled by the directory watcher, which calls this method again.
    private func armFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil

        let descriptor = open(dictionaryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reloadFromDisk()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        fileWatcher = source
    }
}
