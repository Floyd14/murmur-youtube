import Foundation
import ServiceManagement
import Testing

@testable import WisperClone

@MainActor
struct LoginItemTests {
    @Test("reads and refreshes the real service status")
    func refreshesStatus() {
        let service = FakeLoginItemService(status: .notRegistered)
        let manager = LoginItemManager(service: service)

        #expect(manager.status == .notRegistered)

        service.status = .requiresApproval
        manager.refresh()

        #expect(manager.status == .requiresApproval)
    }

    @Test("enabling registers once and exposes the resulting status")
    func enablesLoginItem() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)
        manager.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(service.unregisterCallCount == 0)
        #expect(manager.status == .enabled)
        #expect(manager.error == nil)
    }

    @Test("approval-pending registration can be disabled")
    func disablesPendingApproval() {
        let service = FakeLoginItemService(status: .requiresApproval)
        service.statusAfterUnregister = .notRegistered
        let manager = LoginItemManager(service: service)

        manager.setEnabled(false)

        #expect(service.registerCallCount == 0)
        #expect(service.unregisterCallCount == 1)
        #expect(manager.status == .notRegistered)
    }

    @Test("registration errors stay visible and status is refreshed")
    func exposesRegistrationError() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = TestError.registrationDenied
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(manager.status == .notRegistered)
        #expect(manager.error == "Registrazione negata")
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status?
    var statusAfterUnregister: SMAppService.Status?
    var registerError: Error?
    var unregisterError: Error?

    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { status = statusAfterRegister }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { status = statusAfterUnregister }
    }
}

private enum TestError: LocalizedError {
    case registrationDenied

    var errorDescription: String? {
        "Registrazione negata"
    }
}
