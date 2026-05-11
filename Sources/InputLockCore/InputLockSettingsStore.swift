import Foundation

public final class InputLockSettingsStore {
    private enum Key {
        static let targetInputSourceID = "targetInputSourceID"
        static let isPaused = "isPaused"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> InputLockSettings {
        let storedTarget = defaults.string(forKey: Key.targetInputSourceID)

        return InputLockSettings(
            targetInputSourceID: storedTarget ?? InputLockSettings.defaultTargetInputSourceID,
            isPaused: defaults.object(forKey: Key.isPaused) as? Bool ?? false,
            launchAtLoginEnabled: defaults.object(forKey: Key.launchAtLoginEnabled) as? Bool ?? false
        )
    }

    public func save(_ settings: InputLockSettings) {
        defaults.set(settings.targetInputSourceID, forKey: Key.targetInputSourceID)
        defaults.set(settings.isPaused, forKey: Key.isPaused)
        defaults.set(settings.launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled)
    }
}
