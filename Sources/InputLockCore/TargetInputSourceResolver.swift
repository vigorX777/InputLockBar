import Foundation

public struct TargetInputSourceResolver: Sendable {
    public init() {}

    public func resolve(targetID: String, among sources: [InputSourceDescriptor]) -> InputSourceDescriptor? {
        sources.first { source in
            source.id == targetID && source.isEnabled && source.isSelectable
        }
    }
}
