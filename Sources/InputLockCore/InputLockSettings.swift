import Foundation

public struct InputLockSettings: Equatable, Sendable {
    public static let defaultTargetInputSourceID = "com.tencent.inputmethod.wetype.pinyin"

    public var targetInputSourceID: String
    public var isPaused: Bool
    public var launchAtLoginEnabled: Bool

    public init(
        targetInputSourceID: String = Self.defaultTargetInputSourceID,
        isPaused: Bool = false,
        launchAtLoginEnabled: Bool = false
    ) {
        self.targetInputSourceID = targetInputSourceID
        self.isPaused = isPaused
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
