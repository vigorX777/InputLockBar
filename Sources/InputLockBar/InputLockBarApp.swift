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
