# TouchingBar

TouchingBar 是一个原生 macOS Touch Bar 信息与轻交互工具。它把 Touch Bar 当作 MacBook 上的“灵动岛”：持续显示当前有价值的信息，同时保留少量快捷操作。

项目使用 Swift、AppKit、SwiftUI 和少量隔离的私有系统接口，不包含 WebView、Electron 或网页渲染层。

## 当前能力

### Touch Bar 与配置

- 通过隔离的 `DFRFoundation` 系统模态接口持续占用 Touch Bar，并尽量不随前台应用切换。
- 可以在设置中隐藏系统关闭按钮、关闭动态效果、设置静默启动和菜单栏图标。
- 支持菜单栏切换配置，也支持在 Touch Bar 内容区域上下滑动切换相邻配置。
- 设置窗口采用显式保存流程：发生修改后右下角显示「撤销 / 保存」，也可以按 `⌘S`。
- 支持 F1–F12、Mac 功能键、开发者、音乐与歌词、系统资源和自由组件等配置。

### 内置配置

| 配置 | 主要功能 |
| --- | --- |
| F1–F12 | 完整 12 个功能键，通过 `CGEvent` 发送标准 F1–F12 键码 |
| Mac 功能键 | 屏幕亮度、调度中心、快速锁屏、键盘背光、媒体控制、音量和静音 |
| 开发者 | 路径、Git 分支、改动数量、Python、Node、Java、Go、Rust、Swift、Docker、Kubernetes、Terraform、CMake、Xcode 等上下文 |
| 音乐与歌词 | 媒体控制、当前曲目、歌词、双行歌词和未播放时自动隐藏 |
| 系统资源 | 电池电量、电池功率、预计剩余/充满时间、CPU、GPU、内存、硬盘、CPU 温度、风扇、上传和下载速度；时间组件支持格式切换 |

### 自由组件

自定义配置可以在同一个 Touch Bar 中混合以下组件：

- 媒体控件：上一曲、播放/暂停、下一曲
- 正在播放、歌词
- 日期、时间、日期 + 时间；日期和时间都可以通过下拉菜单切换显示格式
- 系统资源：电池电量、电池功率、电池时间、CPU、GPU、内存、硬盘、CPU 温度、风扇、上传、下载
- 开发者上下文
- 系统功能：调度中心、快速锁屏、亮度、键盘背光、音量和静音
- 自定义按钮：键盘快捷键、启动应用、打开 URL、运行 Shell 命令
- Codex 宠物

组件支持：

- 新添加的组件默认使用常规宽度；之后可以改为紧凑、宽或自定义宽度，自定义范围为 `40...1200 pt`
- 显示标签或隐藏标签
- 隐藏组件
- 拖动排序和上移/下移
- 音乐相关组件可以开启「未播放时隐藏」
- 隐藏组件后会从布局宽度中彻底移除，后面的组件会自动前移

### 音乐与歌词

- 通过系统 Now Playing 读取当前播放信息。
- 网易云音乐支持歌词和翻译，并可获取网易云歌词接口返回的双语歌词。
- Apple Music 可以读取系统歌词；Spotify 目前支持播放状态，但不提供歌词 Provider。
- 支持歌词全局偏移，范围为 `-5...+5` 秒，对所有歌曲生效。
- 双行歌词支持两种下行内容：
  - 有翻译时显示翻译
  - 没有翻译时显示下一句
- 歌词切换动画：下一句上移、放大并过渡为第一行，当前句向上缩小、变灰并退出。
- 设置中的「关闭动态效果」会让宠物、GIF 和双行歌词使用静态切换。
- 「未播放时隐藏」可以让整个音乐预设或单个音乐组件自动隐藏，检测到歌曲后自动恢复。

### Codex 宠物

TouchingBar 支持安装并显示 Codex pet。

标准 pet 目录通常包含：

```text
pet.json
spritesheet.webp
animation-triggers.json   # 可选
```

格式支持：

- 官方 `1536×1872` 精灵图：`8×9` 网格
- 带方向帧的 v2 精灵图：`1536×2288`，`8×11` 网格
- 每格 `192×208`
- `animation-triggers.json` 中的动作状态
- pet 包中的 GIF、PNG、JPEG、WebP、HEIC 等图片资源

安装方式：

- 从 GitHub 安装，支持 HTTPS、SSH 和 `tree/<branch>/<子目录>` 地址
- 从本地目录安装
- 扫描 `~/.codex/pets`
- GitHub 安装内部使用 `git clone --depth 1`

安装后的宠物复制到：

```text
~/Library/Application Support/TouchingBar/Pets/<pet-id>/
```

宠物组件支持选择动作或图片。GIF 和精灵图都会自动循环播放，不会因为原始 GIF 只循环一次而停止。TouchingBar 不内置第三方宠物素材；素材授权仍由原仓库决定。

### 系统资源

- CPU、GPU、内存、硬盘占用率
- CPU 温度和风扇转速
- 电池电量、电池功率，以及使用电池时的预计剩余时间
- 连接充电器时显示预计充满电所需的时间；已充满时显示“已充满”
- 上传、下载速度
- 以每秒采样的滚动折线图展示趋势
- 趋势窗口支持 10 秒、30 秒、1 分钟、2 分钟、5 分钟、10 分钟
- 按当前视口自动缩放；CPU、GPU、内存、硬盘使用 0–100% 范围，温度和网速按当前区间自适应
- 折线图颜色可以通过系统 ColorPicker、`#RRGGBB` 或 RGB 数值设置

### Hook 与自动化

应用内置仅监听回环地址的 Hook 服务：

```text
127.0.0.1:19427
```

支持端点：

```text
POST /v1/context/developer
```

随应用打包的 `TouchingBarCtl` 可以用于终端和脚本：

```bash
TouchingBarCtl health

TouchingBarCtl developer \
  --directory "$PWD" \
  --terminal "VS Code"

TouchingBarCtl install-shell-hook
TouchingBarCtl shell-hook-status
TouchingBarCtl uninstall-shell-hook
```

### 备份与恢复

- 导出/导入 JSON 配置文件。
- 使用 WebDAV `PUT` 上传备份。
- 使用 WebDAV `GET` 下载并恢复配置。
- 兼容自建 NAS 的普通 HTTP WebDAV，但生产环境建议使用 HTTPS。
- WebDAV 密码保存在 macOS 钥匙串，不写入配置文件或备份文件。

## 系统要求

- macOS 13 或更高版本
- 带 Touch Bar 的 MacBook
- 没有 Touch Bar 的 Mac 仍可编译并运行设置界面，但不能显示 Touch Bar UI
- 使用全局占用和键盘事件模拟时，需要授予“辅助功能”权限
- 媒体控制和部分系统动作可能需要自动化权限
- GitHub 宠物安装需要可用的 `git` 命令；SSH 地址需要本机已配置 GitHub SSH Key

全局模式使用 macOS 私有系统模态接口。该接口长期存在于 `DFRFoundation`，但不属于公开 API，macOS 大版本升级后可能需要适配。

## 本地构建

只需要 Xcode Command Line Tools 即可构建应用和核心检查：

```bash
swift build
swift run TouchingBarChecks
```

构建当前机器架构的 App：

```bash
CONFIGURATION=release bash Scripts/build-app.sh
```

构建 Intel 与 Apple Silicon 通用版本：

```bash
CONFIGURATION=release ARCHS="x86_64 arm64" bash Scripts/build-app.sh
```

打包 DMG：

```bash
bash Scripts/build-dmg.sh
```

DMG 中包含拖拽安装背景、`TouchingBar.app` 和指向 `/Applications` 的快捷方式，并会执行 `hdiutil verify` 校验。

产物：

```text
dist/TouchingBar.app
dist/TouchingBar.zip
dist/TouchingBar.dmg
```

开发运行：

```bash
bash Scripts/run-dev.sh
```

## 配置与数据目录

```text
~/Library/Application Support/TouchingBar/config.json
~/Library/Application Support/TouchingBar/runtime-context.json
~/Library/Application Support/TouchingBar/Pets/
~/Library/Application Support/TouchingBar/shell-integration.zsh
```

配置模型带有 schema version。导入旧配置或备份时会检查版本并执行规范化迁移。

## 工程结构

```text
Sources/TouchingBarCore/      数据模型、配置、备份、Hook、宠物、歌词和系统服务
Sources/TouchingBarDFR/       DFRFoundation 私有接口隔离层
Sources/TouchingBar/          AppKit 应用、Touch Bar 控制器、系统集成和 SwiftUI 设置
Sources/TouchingBarCtl/       终端和脚本使用的命令行 Hook 客户端
Sources/TouchingBarChecks/    不依赖 XCTest 的回归检查
```

## 已知边界

- 未安装 shell 集成时，终端目录主要通过前台进程、子进程和 `lsof` 推导；安装 zsh 集成后可以获得更准确的 `$PWD`、虚拟环境和 Node 版本。
- Dock 角标和系统通知横幅读取依赖辅助功能元素；不同 IM 与 macOS 版本可能改变 `AXStatusLabel` 或通知层级，需要增加适配器。TouchingBar 只读取可访问性文本，不修改其他应用。
- 听写、专注模式和部分系统动作依赖 macOS 当前版本及权限；设置中可以把这些按钮替换为快捷键或自定义命令。
- Spotify 目前只提供播放状态，不提供歌词；网易云音乐的歌词和翻译依赖其公开接口。
- Touch Bar 是独立硬件显示区域，高度约 30pt，宠物和长文本都会受到物理尺寸限制。
- 当前构建使用 ad-hoc 签名。正式发布需要 Developer ID 签名与公证。
- TouchingBar 不内置第三方宠物素材；安装到 `Application Support/TouchingBar/Pets` 的宠物仍受原始授权约束。

## CI 与发布

- `.github/workflows/ci.yml` 在 macOS runner 上构建、运行 `TouchingBarChecks`，并生成 `x86_64 + arm64` 通用 App。
- `.github/workflows/dmg.yml` 专门构建通用 App 和 `TouchingBar.dmg`，校验 DMG 后上传 `TouchingBar-dmg` artifact。
- `.github/workflows/release.yml` 在推送 `v*` tag 时构建 ZIP 与 DMG，计算 SHA-256，并创建 GitHub Release。
- Release 会同时发布 `TouchingBar.dmg`、`TouchingBar.dmg.sha256`、`TouchingBar.zip` 和 `TouchingBar.zip.sha256`，DMG 是推荐的安装方式。

从命令行提取产物：

```bash
gh run list --workflow DMG
gh run download <run-id> -n TouchingBar-dmg
```

下载 `TouchingBar.dmg` 后打开映像，将 `TouchingBar.app` 拖入 `Applications` 即可。

## License

MIT
