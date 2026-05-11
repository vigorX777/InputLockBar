# 输入法锁定

一个本地自用的 macOS 菜单栏小工具，用来把输入法固定在你指定的目标输入法上，避免在切换 App 时被系统或应用自动切回 `ABC`。

## 已实现功能

- 菜单栏常驻运行，不出现在 Dock。
- 显示当前状态、锁定目标、当前输入法、当前前台应用。
- 支持把“当前输入法”一键设为锁定目标。
- 支持“暂停自动纠正”。
- 支持“开机自动启动”。
- 监听前台 App 激活后的输入法变化。
- 如果输入法在观察窗内被自动切走，会自动切回目标输入法。
- 手动切换输入法时不会立刻抢回。

## 目录结构

- `Sources/InputLockBar`：菜单栏应用和 macOS 系统集成。
- `Sources/InputLockCore`：可复用的输入法锁定状态机和设置逻辑。
- `Sources/InputLockCoreHarness`：本地自检程序，用来验证核心逻辑。
- `Support`：`Info.plist` 和打包时需要的资源模板。
- `tools`：图标生成与 `.app` 打包脚本。

## 本地开发

需要环境：

- macOS 13+
- Xcode Command Line Tools
- Swift 6

常用命令：

```bash
swift build
swift run InputLockCoreHarness
swift run InputLockBar
```

## 打包应用

执行：

```bash
./tools/package_app.sh
```

打包完成后会生成：

```text
dist/InputLockBar.app
```

如果要安装到本机 `Applications`：

```bash
ditto dist/InputLockBar.app /Applications/InputLockBar.app
open /Applications/InputLockBar.app
```

## GitHub 上传建议

建议只上传源码，不上传这些生成产物：

- `.build`
- `dist`
- `Support/AppIcon-base.png`
- `Support/AppIcon.icns`
- `Support/AppIcon.iconset`

这些都已经写进 `.gitignore`。

## 说明

当前工程是基于 Swift Package 的轻量项目，不是完整的 Xcode `.xcodeproj` 工程。

命令行环境里缺少 `XCTest` / `Testing` 模块，所以核心逻辑测试目前通过 `InputLockCoreHarness` 可执行自检程序完成，而不是标准测试 target。
