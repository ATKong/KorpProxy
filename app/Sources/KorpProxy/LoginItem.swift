import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` to manage the "launch at login"
/// state for the (unsandboxed) menu-bar app.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled { try service.unregister() }
        }
    }
}
