# 输入法锁定

一个用于 macOS 的菜单栏小工具，专门解决“切换 App 时输入法总被切回 `ABC`”的问题。

它会在前台应用切换后的短观察窗内监听输入源变化；如果系统或某个 App 把输入法自动切走，就把它切回你锁定的目标输入法。你手动切换输入法时，它不会立刻抢回来。

## 适合谁

- 经常在中文输入法和英文 App 之间切换。
- 被某些编辑器、终端、浏览器或聊天工具强制切回 `ABC`。
- 想要一个常驻菜单栏、配置简单、只做一件事的小工具。

## 功能

- 菜单栏常驻运行，不出现在 Dock。
- 显示当前状态、锁定目标、当前输入法、当前前台应用。
- 一键把“当前输入法”设为锁定目标。
- 支持“暂停自动纠正”。
- 支持“开机自动启动”。
- 监听前台 App 激活后的输入法变化。
- 如果输入法在观察窗内被自动切走，会自动切回目标输入法。
- 手动切换输入法时不会立刻抢回。
- 自动重试最多 3 次，避免某些 App 激活后延迟改写输入法。

## 使用方式

1. 打开应用后，它会出现在菜单栏。
2. 如果当前目标不是你想要的输入法，先手动切到目标输入法。
3. 点击菜单中的 `将当前输入法设为锁定目标`。
4. 之后在不同 App 间切换时，应用会尽量保持这个输入法不被自动切走。

## 下载与安装

推荐直接从 GitHub Releases 下载压缩包，解压后把 `InputLockBar.app` 拖进 `Applications`。

也可以本地打包：

```bash
./tools/package_app.sh
```

产物位于：

```text
dist/InputLockBar.app
```

安装到本机：

```bash
ditto dist/InputLockBar.app /Applications/InputLockBar.app
open /Applications/InputLockBar.app
```

## 本地开发

环境要求：

- macOS 13+
- Xcode Command Line Tools
- Swift 6

常用命令：

```bash
swift build
swift run InputLockCoreHarness
swift run InputLockBar
```

## 项目结构

- `Sources/InputLockBar`：菜单栏应用和 macOS 系统集成。
- `Sources/InputLockCore`：输入法锁定状态机和设置逻辑。
- `Sources/InputLockCoreHarness`：本地自检程序，用来验证核心逻辑。
- `Support`：`Info.plist` 和打包资源模板。
- `tools`：图标生成、`.app` 打包、Release 打包脚本。

## 测试与验证

当前命令行环境缺少 `XCTest` / `Testing` 模块，所以核心逻辑验证通过可执行自检程序完成：

```bash
swift run InputLockCoreHarness
```

## License

本项目使用 `MIT` License。
