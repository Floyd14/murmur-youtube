import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.andreavisini.wisperclone", category: "audio")
    static let speech = Logger(subsystem: "com.andreavisini.wisperclone", category: "speech")
    static let hotkey = Logger(subsystem: "com.andreavisini.wisperclone", category: "hotkey")
    static let inject = Logger(subsystem: "com.andreavisini.wisperclone", category: "inject")
    static let app = Logger(subsystem: "com.andreavisini.wisperclone", category: "app")
}
