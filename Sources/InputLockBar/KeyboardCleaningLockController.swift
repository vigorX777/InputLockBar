@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
@preconcurrency import Foundation

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

    deinit {
        eventTap.map {
            CGEvent.tapEnable(tap: $0, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
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

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = createEventTap(mask: mask) ?? requestPermissionsAndRetry(mask: mask) else {
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
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        activeTapLocationDescription = nil

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

    return nil
}
