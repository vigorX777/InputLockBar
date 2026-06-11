@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
@preconcurrency import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hidsystem

struct KeyboardCleaningLockState: Equatable {
    var isEnabled: Bool
    var statusText: String
    var needsAttention: Bool
    var canOpenPrivacySettings: Bool

    static let disabled = KeyboardCleaningLockState(
        isEnabled: false,
        statusText: "已关闭",
        needsAttention: false,
        canOpenPrivacySettings: false
    )
}

@MainActor
final class KeyboardCleaningLockController: @unchecked Sendable {
    var onStateChanged: ((KeyboardCleaningLockState) -> Void)?

    private(set) var state = KeyboardCleaningLockState.disabled {
        didSet {
            onStateChanged?(state)
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeTapLocationDescription: String?
    private var hidSystemConnection: io_connect_t = 0
    private var lockedCapsLockState: Bool?
    private var capsLockRestoreTask: Task<Void, Never>?

    deinit {
        capsLockRestoreTask?.cancel()
        eventTap.map {
            CGEvent.tapEnable(tap: $0, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if hidSystemConnection != 0 {
            IOServiceClose(hidSystemConnection)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable(statusText: "已关闭")
        }
    }

    func openPrivacySettings() {
        openSystemSettingsPane("Privacy_ListenEvent")
    }

    func openAccessibilitySettings() {
        openSystemSettingsPane("Privacy_Accessibility")
    }

    private func openSystemSettingsPane(_ pane: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(pane)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func enable() {
        guard !state.isEnabled else {
            return
        }

        prepareCapsLockStateGuard()

        // Media, brightness, playback, and Caps Lock controls arrive as NX_SYSDEFINED (14).
        let systemDefinedEventMask = CGEventMask(1 << 14)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | systemDefinedEventMask

        guard let tap = createEventTap(mask: mask) ?? requestPermissionsAndRetry(mask: mask) else {
            tearDownCapsLockStateGuard(restoreOriginalState: true)
            state = KeyboardCleaningLockState(
                isEnabled: false,
                statusText: permissionFailureStatusText(),
                needsAttention: true,
                canOpenPrivacySettings: true
            )
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            tearDownCapsLockStateGuard(restoreOriginalState: true)
            state = KeyboardCleaningLockState(
                isEnabled: false,
                statusText: "无法创建键盘事件监听",
                needsAttention: true,
                canOpenPrivacySettings: false
            )
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        state = KeyboardCleaningLockState(
            isEnabled: true,
            statusText: activeStatusText(),
            needsAttention: false,
            canOpenPrivacySettings: false
        )
    }

    private func disable(statusText: String) {
        capsLockRestoreTask?.cancel()
        capsLockRestoreTask = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        activeTapLocationDescription = nil
        tearDownCapsLockStateGuard(restoreOriginalState: true)

        state = KeyboardCleaningLockState(
            isEnabled: false,
            statusText: statusText,
            needsAttention: false,
            canOpenPrivacySettings: false
        )
    }

    fileprivate func markTapDisabledBySystem() {
        disable(statusText: "键盘禁用已被系统关闭")
    }

    fileprivate func enforceCapsLockState() {
        guard let lockedCapsLockState,
              hidSystemConnection != 0 else {
            return
        }

        var currentState = false
        guard IOHIDGetModifierLockState(
            hidSystemConnection,
            Int32(kIOHIDCapsLockState),
            &currentState
        ) == KERN_SUCCESS,
        currentState != lockedCapsLockState else {
            return
        }

        IOHIDSetModifierLockState(
            hidSystemConnection,
            Int32(kIOHIDCapsLockState),
            lockedCapsLockState
        )

        capsLockRestoreTask?.cancel()
        capsLockRestoreTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.enforceCapsLockState()
        }
    }

    private func requestInputMonitoringAccessIfNeeded() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }

        return CGRequestListenEventAccess()
    }

    private func requestAccessibilityAccessIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestPermissionsAndRetry(mask: CGEventMask) -> CFMachPort? {
        _ = requestInputMonitoringAccessIfNeeded()
        _ = requestAccessibilityAccessIfNeeded()
        return createEventTap(mask: mask)
    }

    private func createEventTap(mask: CGEventMask) -> CFMachPort? {
        let candidates: [(CGEventTapLocation, String)] = [
            (.cghidEventTap, "HID"),
            (.cgSessionEventTap, "Session"),
            (.cgAnnotatedSessionEventTap, "Annotated Session"),
        ]

        for (location, description) in candidates {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: keyboardCleaningEventCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                continue
            }

            activeTapLocationDescription = description
            return tap
        }

        activeTapLocationDescription = nil
        return nil
    }

    private func activeStatusText() -> String {
        if let activeTapLocationDescription {
            return "键盘已禁用（\(activeTapLocationDescription)），点击关闭恢复输入"
        }

        return "键盘已禁用，点击关闭恢复输入"
    }

    private func permissionFailureStatusText() -> String {
        let listenStatus = CGPreflightListenEventAccess() ? "已允许" : "未允许"
        let accessibilityStatus = AXIsProcessTrusted() ? "已允许" : "未允许"
        return "无法启用：输入监听\(listenStatus)，辅助功能\(accessibilityStatus)"
    }

    private func prepareCapsLockStateGuard() {
        tearDownCapsLockStateGuard(restoreOriginalState: false)

        guard let matching = IOServiceMatching(kIOHIDSystemClass) else {
            return
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return
        }
        defer {
            IOObjectRelease(service)
        }

        var connection: io_connect_t = 0
        guard IOServiceOpen(
            service,
            mach_task_self_,
            UInt32(kIOHIDParamConnectType),
            &connection
        ) == KERN_SUCCESS else {
            return
        }

        var currentState = false
        guard IOHIDGetModifierLockState(
            connection,
            Int32(kIOHIDCapsLockState),
            &currentState
        ) == KERN_SUCCESS else {
            IOServiceClose(connection)
            return
        }

        hidSystemConnection = connection
        lockedCapsLockState = currentState
    }

    private func tearDownCapsLockStateGuard(restoreOriginalState: Bool) {
        if restoreOriginalState,
           let lockedCapsLockState,
           hidSystemConnection != 0 {
            IOHIDSetModifierLockState(
                hidSystemConnection,
                Int32(kIOHIDCapsLockState),
                lockedCapsLockState
            )
        }

        if hidSystemConnection != 0 {
            IOServiceClose(hidSystemConnection)
        }

        hidSystemConnection = 0
        lockedCapsLockState = nil
    }
}

private let keyboardCleaningEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let controller = Unmanaged<KeyboardCleaningLockController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            Task { @MainActor in
                controller.markTapDisabledBySystem()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    if (type == .flagsChanged || type.rawValue == 14), let userInfo {
        let controller = Unmanaged<KeyboardCleaningLockController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        Task { @MainActor in
            controller.enforceCapsLockState()
        }
    }

    return nil
}
