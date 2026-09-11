import Foundation
import Testing
import WisperDictionary
@testable import WisperClone

@MainActor
struct DictionaryStoreTests {
    @Test("un salvataggio fallito conserva stato e segnala l'errore")
    func failedSaveIsTransactional() throws {
        let fixture = try Fixture(initialContents: "Voce iniziale\n")
        defer { fixture.remove() }

        let store = DictionaryStore(
            fileURL: fixture.dictionaryURL,
            installStarterDictionary: false,
            watchChanges: false
        )
        let originalEntries = store.entries
        let originalRevision = store.revision

        try FileManager.default.removeItem(at: fixture.directoryURL)
        try "impedisce di ricreare la cartella".write(
            to: fixture.directoryURL,
            atomically: true,
            encoding: .utf8
        )

        let didSave = store.add(.term("Nuova voce"))

        #expect(!didSave)
        #expect(store.entries == originalEntries)
        #expect(store.revision == originalRevision)
        #expect(store.persistenceError?.contains("Impossibile salvare") == true)
    }

    @Test("il watcher rileva sostituzioni e scritture dirette del file")
    func watcherHandlesReplacementAndInPlaceWrite() async throws {
        let fixture = try Fixture(initialContents: "Prima voce\n")
        defer { fixture.remove() }

        let store = DictionaryStore(
            fileURL: fixture.dictionaryURL,
            installStarterDictionary: false,
            watchChanges: true
        )
        #expect(store.entries.map(\.write) == ["Prima voce"])

        try FileManager.default.removeItem(at: fixture.dictionaryURL)
        try await waitUntil { store.persistenceError != nil }
        #expect(store.entries.map(\.write) == ["Prima voce"])

        try "Seconda voce\n".write(to: fixture.dictionaryURL, atomically: true, encoding: .utf8)
        try await waitUntil { store.entries.map(\.write) == ["Seconda voce"] }
        #expect(store.persistenceError == nil)

        try "Terza voce\n".write(to: fixture.dictionaryURL, atomically: false, encoding: .utf8)
        try await waitUntil { store.entries.map(\.write) == ["Terza voce"] }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timeout in attesa dell'evento del file system")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct Fixture {
    let rootURL: URL
    let directoryURL: URL
    let dictionaryURL: URL

    init(initialContents: String) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WisperCloneTests-\(UUID().uuidString)", isDirectory: true)
        directoryURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        dictionaryURL = directoryURL.appendingPathComponent("dictionary.txt")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try initialContents.write(to: dictionaryURL, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
