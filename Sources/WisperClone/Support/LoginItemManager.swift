import Foundation
import Observation
import ServiceManagement

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

@MainActor
private final class MainAppLoginItemService: LoginItemServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

/// Owns the system registration that launches WisperClone at the user's next login.
///
/// The status is deliberately read from ServiceManagement instead of being persisted as a
/// preference: the user can revoke approval in System Settings while the app is running.
@MainActor
@Observable
final class LoginItemManager {
    static let shared = LoginItemManager(service: MainAppLoginItemService())

    private let service: any LoginItemServicing

    private(set) var status: SMAppService.Status
    private(set) var error: String?

    init(service: any LoginItemServicing) {
        self.service = service
        status = service.status
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        error = nil
        refresh()

        do {
            if enabled {
                guard status != .enabled, status != .requiresApproval else { return }
                try service.register()
            } else {
                guard status != .notRegistered else { return }
                try service.unregister()
            }
        } catch {
            self.error = error.localizedDescription
        }

        refresh()
    }
}
