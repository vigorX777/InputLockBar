import Foundation

public struct InputSourceDescriptor: Equatable, Sendable {
    public let id: String
    public let localizedName: String?
    public let isSelectable: Bool
    public let isEnabled: Bool

    public init(id: String, localizedName: String?, isSelectable: Bool, isEnabled: Bool) {
        self.id = id
        self.localizedName = localizedName
        self.isSelectable = isSelectable
        self.isEnabled = isEnabled
    }

    public var displayName: String {
        localizedName ?? id
    }
}
