import Foundation
import Observation

enum RecognitionLanguage: String, CaseIterable, Sendable {
    case italian
    case automatic
    case english

    var locale: Locale {
        switch self {
        case .italian: Locale(identifier: "it-IT")
        case .automatic: .current
        case .english: Locale(identifier: "en-US")
        }
    }

    var displayName: String {
        switch self {
        case .italian: "Italiano"
        case .automatic: "Automatico"
        case .english: "Inglese"
        }
    }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var pushToTalkKey: PushToTalkKey {
        didSet { defaults.set(pushToTalkKey.rawValue, forKey: Keys.pushToTalkKey) }
    }

    var recognitionLanguage: RecognitionLanguage {
        didSet { defaults.set(recognitionLanguage.rawValue, forKey: Keys.recognitionLanguage) }
    }

    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pushToTalkKey = "pushToTalkKey"
        static let recognitionLanguage = "recognitionLanguage"
        static let cleanupEnabled = "cleanupEnabled"
        static let smartCleanup = "smartCleanup"
        static let soundEnabled = "soundEnabled"
    }

    private init() {
        let hotkey = defaults.string(forKey: Keys.pushToTalkKey) ?? PushToTalkKey.rightOption.rawValue
        pushToTalkKey = PushToTalkKey(rawValue: hotkey) ?? .rightOption

        let language = defaults.string(forKey: Keys.recognitionLanguage)
        recognitionLanguage = RecognitionLanguage(rawValue: language ?? "") ?? .italian

        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        smartCleanup = defaults.object(forKey: Keys.smartCleanup) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
    }
}
