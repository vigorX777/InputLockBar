import AppKit
import Combine
import Foundation
import InputLockCore

@MainActor
final class InputLockMonitor: ObservableObject {
    @Published private(set) var statusText = "启动中"
    @Published private(set) var currentInputSourceID: String?
    @Published private(set) var currentDisplayName = "未知"
    @Published private(set) var targetDisplayName = InputLockSettings.defaultTargetInputSourceID
    @Published private(set) var frontmostAppDisplayName = "未知"
    @Published private(set) var menuBarSymbolName = "keyboard"
    @Published private(set) var launchAtLoginAvailable = true
    @Published private(set) var isPaused: Bool
    @Published private(set) var launchAtLoginEnabled: Bool

    private let settingsStore: InputLockSettingsStore
    private let inputSourceController: InputSourceControlling
    private let loginItemController: LaunchAtLoginControlling
    private let resolver = TargetInputSourceResolver()

    private var engine: InputLockEngine
    private var targetDescriptor: InputSourceDescriptor?
    private var workspaceObserver: NSObjectProtocol?
    private var correctionTask: Task<Void, Never>?
    private var scheduledCorrectionToken: Int?

    init(
        settingsStore: InputLockSettingsStore = InputLockSettingsStore(),
        inputSourceController: InputSourceControlling = CarbonInputSourceController(),
        loginItemController: LaunchAtLoginControlling = MainAppLoginItemController()
    ) {
        let settings = settingsStore.load()
        self.settingsStore = settingsStore
        self.inputSourceController = inputSourceController
        self.loginItemController = loginItemController
        engine = InputLockEngine(
            targetInputSourceID: settings.targetInputSourceID,
            isPaused: settings.isPaused
        )
        isPaused = settings.isPaused
        launchAtLoginEnabled = settings.launchAtLoginEnabled

        inputSourceController.onSelectedInputSourceChanged = { [weak self] descriptor in
            guard let self else {
                return
            }

            self.handleInputSourceChanged(descriptor)
        }

        inputSourceController.start()
        launchAtLoginAvailable = loginItemController.isAvailable
        refreshLaunchAtLoginState()
        startObservingWorkspace()
        refreshStateFromSystem()
    }

    func captureCurrentInputSourceAsTarget() {
        guard let currentDescriptor = inputSourceController.currentInputSource() else {
            statusText = "无法读取当前输入法"
            updateMenuBarPresentation()
            return
        }

        applySettings(InputLockSettings(
            targetInputSourceID: currentDescriptor.id,
            isPaused: isPaused,
            launchAtLoginEnabled: launchAtLoginEnabled
        ))
        statusText = "已锁定为 \(currentDescriptor.displayName)"
        refreshStateFromSystem()
    }

    func setPaused(_ paused: Bool) {
        applySettings(InputLockSettings(
            targetInputSourceID: engine.targetInputSourceID,
            isPaused: paused,
            launchAtLoginEnabled: launchAtLoginEnabled
        ))
        refreshStateFromSystem()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard launchAtLoginAvailable else {
            launchAtLoginEnabled = false
            return
        }

        do {
            try loginItemController.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            persistSettings()
            statusText = enabled ? "已开启开机自动启动" : "已关闭开机自动启动"
        } catch {
            launchAtLoginEnabled = loginItemController.currentState()
            statusText = "设置开机启动失败：\(error.localizedDescription)"
        }

        updateMenuBarPresentation()
    }

    private func applySettings(_ settings: InputLockSettings) {
        let previousPendingToken = engine.pendingCorrectionToken
        engine.applySettings(settings)
        isPaused = settings.isPaused
        launchAtLoginEnabled = settings.launchAtLoginEnabled
        persistSettings()
        syncScheduledCorrection(previousPendingToken: previousPendingToken)
    }

    private func persistSettings() {
        settingsStore.save(InputLockSettings(
            targetInputSourceID: engine.targetInputSourceID,
            isPaused: isPaused,
            launchAtLoginEnabled: launchAtLoginEnabled
        ))
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = loginItemController.currentState()
        persistSettings()
    }

    private func startObservingWorkspace() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let displayName = app?.localizedName ?? bundleID ?? "未知"

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.frontmostAppDisplayName = displayName
                self.engine.handleAppActivated(bundleID: bundleID, at: self.timestamp())
                self.updateStatusText()
                self.updateMenuBarPresentation()
            }
        }
    }

    private func refreshStateFromSystem() {
        let currentDescriptor = inputSourceController.currentInputSource()
        currentInputSourceID = currentDescriptor?.id
        currentDisplayName = currentDescriptor?.displayName ?? "未知"

        let enabledSources = inputSourceController.enabledInputSources()
        targetDescriptor = resolver.resolve(targetID: engine.targetInputSourceID, among: enabledSources)
        targetDisplayName = targetDescriptor?.displayName ?? engine.targetInputSourceID

        updateStatusText()
        updateMenuBarPresentation()
    }

    private func handleInputSourceChanged(_ descriptor: InputSourceDescriptor?) {
        currentInputSourceID = descriptor?.id
        currentDisplayName = descriptor?.displayName ?? "未知"

        let enabledSources = inputSourceController.enabledInputSources()
        targetDescriptor = resolver.resolve(targetID: engine.targetInputSourceID, among: enabledSources)
        targetDisplayName = targetDescriptor?.displayName ?? engine.targetInputSourceID

        guard let inputSourceID = descriptor?.id else {
            statusText = "无法读取当前输入法"
            updateMenuBarPresentation()
            return
        }

        let previousPendingToken = engine.pendingCorrectionToken
        let reaction = engine.handleInputSourceChanged(to: inputSourceID, at: timestamp())
        syncScheduledCorrection(previousPendingToken: previousPendingToken)
        process(reaction)
        updateStatusText()
        updateMenuBarPresentation()
    }

    private func process(_ reaction: EngineReaction) {
        guard let correction = reaction.correction else {
            if reaction.clearedPendingCorrection {
                scheduledCorrectionToken = nil
            }
            return
        }

        scheduleCorrection(correction)
    }

    private func scheduleCorrection(_ correction: CorrectionRequest) {
        if scheduledCorrectionToken != correction.token {
            correctionTask?.cancel()
        }

        scheduledCorrectionToken = correction.token
        correctionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let delayNanoseconds = UInt64(correction.delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await self.performCorrection(correction)
        }
    }

    private func performCorrection(_ correction: CorrectionRequest) async {
        guard engine.pendingCorrectionToken == correction.token else {
            return
        }

        engine.noteCorrectionAttemptStarted(token: correction.token, at: timestamp())
        let didSelectTarget = inputSourceController.selectInputSource(id: correction.targetInputSourceID)

        let verificationDelay = UInt64(InputLockEngine.correctionDelay * 1_000_000_000)
        try? await Task.sleep(nanoseconds: verificationDelay)
        guard !Task.isCancelled else {
            return
        }

        let currentDescriptor = inputSourceController.currentInputSource()
        currentInputSourceID = currentDescriptor?.id
        currentDisplayName = currentDescriptor?.displayName ?? "未知"

        let enabledSources = inputSourceController.enabledInputSources()
        targetDescriptor = resolver.resolve(targetID: engine.targetInputSourceID, among: enabledSources)
        targetDisplayName = targetDescriptor?.displayName ?? engine.targetInputSourceID

        let previousPendingToken = engine.pendingCorrectionToken
        let reaction = engine.handlePostCorrectionCheck(
            token: correction.token,
            currentInputSourceID: currentDescriptor?.id ?? "",
            at: timestamp()
        )
        syncScheduledCorrection(previousPendingToken: previousPendingToken)

        if !didSelectTarget && reaction.correction == nil {
            statusText = "目标输入法不可用或无法切换"
        }

        process(reaction)
        updateStatusText()
        updateMenuBarPresentation()
    }

    private func syncScheduledCorrection(previousPendingToken: Int?) {
        guard previousPendingToken != engine.pendingCorrectionToken else {
            return
        }

        if engine.pendingCorrectionToken == nil {
            correctionTask?.cancel()
            correctionTask = nil
            scheduledCorrectionToken = nil
        }
    }

    private func updateStatusText() {
        if isPaused {
            statusText = "已暂停"
            return
        }

        if targetDescriptor == nil {
            statusText = "目标输入法不可用"
            return
        }

        if engine.pendingCorrectionToken != nil {
            statusText = "正在切回锁定输入法"
            return
        }

        if currentInputSourceID == engine.targetInputSourceID {
            statusText = "已锁定"
            return
        }

        statusText = "正在监听应用触发的切换"
    }

    private func updateMenuBarPresentation() {
        if isPaused {
            menuBarSymbolName = "pause.circle"
        } else if targetDescriptor == nil {
            menuBarSymbolName = "exclamationmark.triangle"
        } else if currentInputSourceID == engine.targetInputSourceID {
            menuBarSymbolName = "lock.circle"
        } else {
            menuBarSymbolName = "keyboard"
        }
    }

    private func timestamp() -> TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }
}
