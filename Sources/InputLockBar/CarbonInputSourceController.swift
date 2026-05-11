import AppKit
import Carbon
import InputLockCore

@MainActor
protocol InputSourceControlling: AnyObject {
    var onSelectedInputSourceChanged: ((InputSourceDescriptor?) -> Void)? { get set }
    func start()
    func stop()
    func currentInputSource() -> InputSourceDescriptor?
    func enabledInputSources() -> [InputSourceDescriptor]
    func selectInputSource(id: String) -> Bool
}

@MainActor
final class CarbonInputSourceController: InputSourceControlling {
    var onSelectedInputSourceChanged: ((InputSourceDescriptor?) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else {
            return
        }

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.onSelectedInputSourceChanged?(self.currentInputSource())
            }
        }
    }

    func stop() {
        guard let observer else {
            return
        }

        DistributedNotificationCenter.default().removeObserver(observer)
        self.observer = nil
    }

    func currentInputSource() -> InputSourceDescriptor? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        return descriptor(for: source)
    }

    func enabledInputSources() -> [InputSourceDescriptor] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        return list.compactMap { item in
            descriptor(for: item as! TISInputSource)
        }
    }

    func selectInputSource(id: String) -> Bool {
        let properties = [kTISPropertyInputSourceID as String: id] as NSDictionary
        let list = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray

        for item in list {
            let source = item as! TISInputSource
            guard let descriptor = descriptor(for: source),
                  descriptor.isEnabled,
                  descriptor.isSelectable else {
                continue
            }

            return TISSelectInputSource(source) == noErr
        }

        return false
    }

    private func descriptor(for source: TISInputSource) -> InputSourceDescriptor? {
        guard let id = stringProperty(kTISPropertyInputSourceID, source: source) else {
            return nil
        }

        return InputSourceDescriptor(
            id: id,
            localizedName: stringProperty(kTISPropertyLocalizedName, source: source),
            isSelectable: booleanProperty(kTISPropertyInputSourceIsSelectCapable, source: source),
            isEnabled: booleanProperty(kTISPropertyInputSourceIsEnabled, source: source)
        )
    }

    private func stringProperty(_ key: CFString, source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func booleanProperty(_ key: CFString, source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }

        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
