import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isAvailable: Bool { get }
    func currentState() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class MainAppLoginItemController: LaunchAtLoginControlling {
    var isAvailable: Bool {
        if #available(macOS 13.0, *) {
            return true
        }

        return false
    }

    func currentState() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notFound, .notRegistered:
            return false
        @unknown default:
            return false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
