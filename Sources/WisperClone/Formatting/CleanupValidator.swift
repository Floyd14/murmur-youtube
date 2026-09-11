import Foundation

enum CleanupValidator {
    private static let hesitations: Set<String> = ["um", "uh", "erm", "uhm", "hmm", "mhm", "ehm", "mmm"]

    static func preservesWords(original: String, cleaned: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.precomposedStringWithCanonicalMapping.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !hesitations.contains($0) }
        }
        let expected = words(original)
        return !expected.isEmpty && expected == words(cleaned)
    }
}
