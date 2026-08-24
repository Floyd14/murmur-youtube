import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.andreavisini.wisperclone.app", category: "audio")
    static let speech = Logger(subsystem: "com.andreavisini.wisperclone.app", category: "speech")
    static let hotkey = Logger(subsystem: "com.andreavisini.wisperclone.app", category: "hotkey")
    static let inject = Logger(subsystem: "com.andreavisini.wisperclone.app", category: "inject")
    static let app = Logger(subsystem: "com.andreavisini.wisperclone.app", category: "app")
}
