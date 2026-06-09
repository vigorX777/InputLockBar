import AppKit
import SwiftUI

@main
struct InputLockBarApp: App {
    @StateObject private var monitor = InputLockMonitor()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("输入法锁定", systemImage: monitor.menuBarSymbolName) {
            InputLockMenuView(monitor: monitor)
        }
    }
}

private struct InputLockMenuView: View {
    @ObservedObject var monitor: InputLockMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态：\(monitor.statusText)")
            Text("锁定目标：\(monitor.targetDisplayName)")
            Text("当前输入法：\(monitor.currentDisplayName)")
            Text("当前应用：\(monitor.frontmostAppDisplayName)")

            Divider()

            Button("将当前输入法设为锁定目标") {
                monitor.captureCurrentInputSourceAsTarget()
            }
            .disabled(monitor.currentInputSourceID == nil)

            Toggle("暂停自动纠正", isOn: Binding(
                get: { monitor.isPaused },
                set: { monitor.setPaused($0) }
            ))

            Divider()

            Text("键盘清洁：\(monitor.keyboardCleaningStatusText)")

            Toggle("键盘清洁模式", isOn: Binding(
                get: { monitor.isKeyboardCleaningModeEnabled },
                set: { monitor.setKeyboardCleaningModeEnabled($0) }
            ))

            if monitor.canOpenKeyboardPrivacySettings {
                Button("打开输入监听设置") {
                    monitor.openKeyboardPrivacySettings()
                }

                Button("打开辅助功能设置") {
                    monitor.openKeyboardAccessibilitySettings()
                }
            }

            Toggle("开机自动启动", isOn: Binding(
                get: { monitor.launchAtLoginEnabled },
                set: { monitor.setLaunchAtLoginEnabled($0) }
            ))
            .disabled(!monitor.launchAtLoginAvailable)

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
    }
}
