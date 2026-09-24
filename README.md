# TouchingBar

TouchingBar 是一个原生 macOS Touch Bar 信息与轻交互工具。目标不是复制完整的 BetterTouchTool，而是把 Touch Bar 当成 MacBook 上的“灵动岛”：持续展示当前有价值的信息，并保留少量快捷操作。

项目使用 Swift、AppKit 与 SwiftUI，不包含 WebView、Electron 或网页渲染层。

## 已实现能力

- **全局占用 Touch Bar**：通过隔离的 `DFRFoundation` 系统模态接口，让 TouchingBar 不随前台应用切换，并隐藏系统关闭按钮。
- **多配置切换**：Touch Bar 最右侧固定显示 `‹ 配置名称 ›`，可以快速切换配置。
- **F1–F12 配置**：始终显示完整的 12 个功能键，并通过 `CGEvent` 发送标准 F1–F12 键码。
- **Mac 功能键配置**：默认按照屏幕亮度、调度中心、快速锁屏、键盘背光、媒体和音量排列，所有按钮均可在设置中替换。
- **开发者上下文配置**：在 Terminal、iTerm2、VS Code、JetBrains IDE、Warp、WezTerm、kitty、Alacritty 等前台时，尝试获取当前 shell 的目录，并展示 Git 分支、改动数量、Python 虚拟环境与版本、Node 包管理器及版本信息。
- **zsh 终端集成**：可显式安装带标记的 shell hook，在目录变化时上报真实 `$PWD`、虚拟环境和 Node 版本，并支持一键卸载。
- **Agent Hook 配置**：本地监听 `127.0.0.1:19427`，按 session 维护多个 Agent 会话，展示状态、任务、事件、工具和工作目录，并支持等待/完成/失败通知。
- **歌词全局偏移**：可在设置中统一调整歌词提前或延后时间，偏移对所有歌曲生效；Touch Bar 以 0.5 秒周期刷新当前歌词。
- **系统资源预设**：展示 CPU、GPU、内存、硬盘、CPU 温度、风扇转速及上传/下载速度。
- **自由组件**：自定义预设可以在同一 Touch Bar 中混合动作按钮、系统资源、开发者信息、Agent 会话、消息和音乐歌词。
- **消息配置**：从 Dock 角标读取微信、QQ、Telegram、企业微信、飞书和 Lark 的未读数；在获得辅助功能权限后，尝试读取系统通知横幅的发送者与正文，并支持自定义消息 Hook。Touch Bar 通知可以关闭。
- **菜单栏模式**：菜单栏图标可以显示或隐藏，并提供配置切换、重新显示 Touch Bar和退出等功能。
- **备份与恢复**：支持 JSON 文件导入导出，以及通过 WebDAV `PUT/GET` 上传和恢复配置。
- **Intel 与 Apple Silicon**：构建脚本与 GitHub Actions 会分别构建 `x86_64` 与 `arm64`，发布时使用 `lipo` 合成为通用二进制。

## 系统要求

- macOS 13 或更高版本
- 带 Touch Bar 的 MacBook；没有 Touch Bar 的 Mac 仍可编译和运行设置界面，但不能显示 Touch Bar UI
- 使用全局占用、Dock 角标读取和键盘事件模拟时，需要授予“辅助功能”权限
- 音乐控制需要授予自动化权限

全局模式使用 macOS 私有系统模态接口。该接口长期存在于 `DFRFoundation`，LyricsX、BetterTouchTool 等应用也采用类似机制，但它不属于公开 API，macOS 大版本升级后可能需要适配。

## 本地构建

只需要 Xcode Command Line Tools 即可构建应用和核心检查：

```bash
swift build
swift run TouchingBarChecks
bash Scripts/build-app.sh
open dist/TouchingBar.app
```

默认只构建当前机器架构。构建通用版本：

```bash
ARCHS="x86_64 arm64" bash Scripts/build-app.sh
```

产物位于：

```text
dist/TouchingBar.app
dist/TouchingBar.zip
```

开发时可以运行：

```bash
bash Scripts/run-dev.sh
```

## 配置与数据

配置文件和运行时上下文默认保存在：

```text
~/Library/Application Support/TouchingBar/config.json
~/Library/Application Support/TouchingBar/runtime-context.json
```

配置模型支持版本号。恢复时会检查 schema/备份格式，并将旧配置规范化到当前版本。

## Hook 接入

应用内会启动仅监听回环地址的 Hook 服务。也可以使用随应用打包的 `TouchingBarCtl`：

```bash
TouchingBarCtl health

TouchingBarCtl agent \
  --provider codex \
  --status running \
  --task "Implement Touch Bar preset"

TouchingBarCtl developer \
  --directory "$PWD" \
  --terminal "VS Code"

TouchingBarCtl install-shell-hook
TouchingBarCtl shell-hook-status
TouchingBarCtl uninstall-shell-hook

TouchingBarCtl message \
  --app WeChat \
  --sender Alice \
  --body "Hello from a hook"
```

如果厂商提供的是原始事件 JSON，可以直接把原始 payload 从标准输入交给归一化端点：

```bash
TouchingBarCtl agent-event --provider claude-code < raw-hook.json
```

归一化器支持常见的 `hook_event_name/type/status`、`session_id`、`prompt/task`、`tool_name` 字段，并把 `PreToolUse`、`UserPromptSubmit` 等事件映射为 `running`，`Stop` 映射为 `completed`。未知字段不会阻止上报。

直接发送 TouchingBar 自己的 JSON：

```bash
curl -X POST http://127.0.0.1:19427/v1/context/agent \
  -H 'Content-Type: application/json' \
  -d '{"provider":"claude-code","status":"running","task":"Run tests","updatedAt":"2026-09-23T06:00:00Z"}'
```

开发者上下文只会覆盖 Hook 上报的字段；对于本地项目，`TouchingBarCtl developer` 会先补齐 Git、Python 和 Node 信息。也可以在“设置 > 集成”安装 zsh 集成，让 shell 在目录变化时直接上报真实的 `$PWD`、虚拟环境和 Node 版本：

```bash
curl -X POST http://127.0.0.1:19427/v1/context/developer \
  -H 'Content-Type: application/json' \
  -d '{"workingDirectory":"/Users/me/project","terminalName":"JetBrains","updatedAt":"2026-09-23T06:00:00Z"}'
```

消息 Hook：

```bash
curl -X POST http://127.0.0.1:19427/v1/messages \
  -H 'Content-Type: application/json' \
  -d '{"application":"WeChat","sender":"Alice","body":"你好","unreadCount":1,"receivedAt":"2026-09-23T06:00:00Z"}'
```

## WebDAV

在“设置 > 备份与恢复”中填写 WebDAV 服务器、用户名、密码与远程路径。为了兼容自建 NAS 的普通 HTTP WebDAV，应用允许用户配置的 HTTP 地址；生产环境仍建议使用 HTTPS。当前实现通过 HTTP Basic Authentication 执行：

- `PUT` 上传完整配置
- `GET` 下载并发恢复
- 本地导出/导入 JSON 备份文件

密码不会写进配置和备份文件，只保留在当前设置会话中。后续应迁移到 Keychain 以便长期保存。

## 工程结构

```text
Sources/TouchingBarCore/      跨进程可复用的数据模型、配置、Hook、备份服务
Sources/TouchingBarDFR/       DFRFoundation 私有接口隔离层
Sources/TouchingBar/          AppKit 应用、系统集成、Touch Bar 与 SwiftUI 设置
Sources/TouchingBarCtl/       面向 Agent、终端和脚本的命令行 Hook 客户端
Sources/TouchingBarChecks/    不依赖 XCTest 的核心回归检查
```

## 已知边界

- 未安装 shell 集成时，终端目录主要通过前台进程子进程与 `lsof` 推导；安装 zsh 集成后可以获得更准确的目录与运行时环境。
- Dock 角标和系统消息横幅读取依赖辅助功能元素；不同 IM 与 macOS 版本可能改变 `AXStatusLabel` 或通知层级，需要增加适配器。该实现只读取可访问性文本，不修改其他应用。
- 听写、专注模式等系统动作依赖 macOS 当前版本，无法在无辅助功能权限时完全模拟。设置中可以把这些按钮替换成自定义快捷键或命令。
- 音乐歌词目前优先读取 Apple Music 当前曲目的歌词；Spotify 与尚未实现的流媒体播放器需要额外 Provider。
- 当前构建使用 ad-hoc 签名。正式发布时需要 Developer ID 签名、公证与 Keychain 存储 WebDAV 密码。

## CI 与发布

- `.github/workflows/ci.yml` 在 Intel 与 Apple Silicon runner 上构建并运行核心检查。
- `.github/workflows/release.yml` 构建通用二进制、计算 SHA-256，并在推送 `v*` tag 时创建 GitHub Release。

## License

MIT
