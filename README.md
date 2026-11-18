# zero-beat GUI · 零拍图形客户端

面向 **Android、Linux 与 macOS 桌面**（Windows 为 P7 候选）的 [zero-beat](https://github.com/Sheyiyuan/zero-beat) 图形客户端。

界面用 Flutter 重写；曲库、搜索、登录、下载、同步和播放决策通过公开 Go `session` SDK 复用；声音由 Dart 侧的 libmpv（media_kit）输出。

> **状态：完整功能接入与平台验收进行中，0.8.0 未发布。** 已有 Session、原生动态库、RPC、Linux / Android 独立界面和 media_kit 播放接线。支持歌单浏览与分页、搜索与分页、链接播放、播放队列、手动重连与 Android 音频焦点协调。构建和设备验证的实际结果见[首批验收记录](docs/16-first-gui-validation.md)。技术选型与取舍见 [docs/09-evaluation.md](docs/09-evaluation.md) 和 [docs/decisions/](docs/decisions/)。

> **发布安排：TUI / core 的 v0.8.0 暂不发布，等待 GUI 完成并通过联合验收后一起发布。** GUI 保留独立应用版本规划。已完成的接口与 TUI 行为见 [0.8.0 更新说明](https://github.com/Sheyiyuan/zero-beat-tui/blob/main/docs/release-notes-v0.8.0.md)。

core / TUI 模块拆分、媒体与键位解耦、go-git 后端和写前校验已落地；评论、相关推荐、用户／歌手主页、播客电台接口已在 TUI 接入并回归。GUI 已接入账号、曲库批量操作、歌词、评论／相关推荐、主页／电台、下载和同步页面；当前继续完成双端功能与异常路径验收。逐项证据和剩余验收见[完整功能验收](docs/17-full-gui-parity.md)，TUI 验证不能替代 GUI 平台验收。

## 目标平台

| 平台 | 优先级 | 说明 |
| --- | --- | --- |
| Android | P0 | 触屏曲库与播放、后台播放、媒体通知/锁屏、跨设备同步 |
| Linux 桌面 | P1 | 与 TUI 共用数据、同一把实例锁、托盘/小窗继续播放、MPRIS |
| macOS | P1 | 与 TUI 共用 `~/Library/Application Support/zero-beat`、非沙盒、DMG 公证（[11-macos](docs/11-macos.md)） |
| Windows | P7 候选 | GUI 可适配；需要 Windows 构建环境，排在 v0.1 之后（[10-windows](docs/10-windows.md)） |
| iOS | **不做** | 与 macOS 无关：不做 iOS 目标、不构建 |

## 和 zero-beat 的关系

- 数据共享：桌面复用 TUI 的目录解析；Linux 默认 `~/.config/zero-beat/`，尊重 `XDG_CONFIG_HOME`；macOS 使用 `~/Library/Application Support/zero-beat`；Windows 使用 `%APPDATA%\zero-beat`；跨设备只共享同步仓库，新建使用 `meta.v=3`，已有 v2 加密仓库继续兼容。登录态同步默认关闭，每台设备单独启用。
- 本地布局：本仓库作为集成仓库 zero-beat 的 `zero-beat-gui/` 子模块，与 core、TUI 并列；历史导入来源见 [IMPORT.md](IMPORT.md)。
- 代码复用：GUI 通过公开 Session 门面使用核心，**不 import `internal/`**，也不 fork/复制。核心对 oto/Bubble Tea 的传递依赖已在 TUI 阶段移除。
- 同步不 fork：git CLI / go-git 两个后端都放在 zero-beat 的 sync 包里，GUI 只选后端；仓库格式与合并逻辑只有一份。
- 界面独立：TUI 继续存在，面向终端；GUI 桌面鼠标优先、提供常用快捷键，Android 触控优先。两端分别设计导航、布局和返回方式，复用业务模型与视觉规范。
- 互斥：桌面端 GUI 与 TUI 共用 `instance.lock`，同一数据目录只能有一个在运行；Android 没有 TUI，不需要这把锁。

## 关键决策

| 决策 | 内容 | 记录 |
| --- | --- | --- |
| 技术栈 | Flutter UI + Go 核心（Linux/Android/macOS c-shared，Windows sidecar）+ 本机 NDJSON RPC | [ADR-0002](docs/decisions/0002-stack.md) |
| 模块边界 | zero-beat 新增公开 `session` / `sync`；GUI 不 import `internal/` | [ADR-0006](docs/decisions/0006-module-boundary.md) |
| 播放 | Go `player.Controller` 保留队列/模式/重试；Dart 用 media_kit 做音频引擎，loudnorm 保留 | [ADR-0003](docs/decisions/0003-playback.md) |
| Android 下载 | Go 共享传输；原生 libav 无损封装并写入歌名／歌手／专辑，不执行外部 ffmpeg | [ADR-0009](docs/decisions/0009-android-download.md) |
| 进程与生命周期 | Linux/Android/macOS 单进程；Windows 为 `zero-core.exe` sidecar；关窗退到小窗/托盘/Dock 继续播放 | [ADR-0004](docs/decisions/0004-single-instance.md) |
| 数据与同步 | SQLite 本机；共用 core 同步格式与默认关闭的登录态同步；每轮开始前选择 git CLI / go-git，业务失败不中途切换 | [ADR-0005](docs/decisions/0005-sync.md) |
| macOS | 非沙盒以共享 TUI 数据；Developer ID + 公证；不走 Mac App Store | [ADR-0008](docs/decisions/0008-macos.md) |
| 平台范围 | Android + Linux + macOS；Windows 为 P7 候选；iOS 不做 | [ADR-0001](docs/decisions/0001-targets.md) |

## 架构一览

```
┌────────────────── Flutter App（Linux/Android/macOS 单进程） ──────────────┐
│  UI（手机 / 桌面独立设计）        audio_service / 通知 / 锁屏 / 托盘      │
│        │                                   │                             │
│        └──────────────┬────────────────────┘                             │
│                       │ 引擎命令 / 播放状态                               │
│                 media_kit（libmpv）                                       │
│                       │                                                   │
│   Go 核心（Linux/Android: libzero.so；macOS: libzero.dylib；Windows: exe）│
│   session（session/DTO/Engine）· store · app · player · sync · instance  │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ NDJSON / JSON-RPC（桌面回环／Android 私有 socket，随机 token）
                                │
             UI 与 Go 核心同进程（Windows 为子进程），RPC 只是语言边界
```

桌面端另有：

```
TUI（zero） ── 同一把 instance.lock ── GUI（Flutter）
```

> Windows 用 `zero-core.exe` sidecar，避免 MinGW 编 Go DLL；Linux/Android 用 `libzero.so`，macOS 用 `libzero.dylib`。RPC 协议四端一致。

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [00-overview](docs/00-overview.md) | 目标、非目标、术语、兼容承诺、设计原则 |
| [01-architecture](docs/01-architecture.md) | 进程模型、层次、启动序列、播放数据流、失败处理 |
| [02-rpc](docs/02-rpc.md) | 传输、信封、方法/事件清单、DTO 规则、安全 |
| [03-playback](docs/03-playback.md) | 播放分工、loudnorm、片段、Android/macOS/Windows 系统组件 |
| [04-sync-and-data](docs/04-sync-and-data.md) | sync v2 字节契约、三方合并/提交历史、SQLite、Android 下载与存储 |
| [05-lock-and-lifecycle](docs/05-lock-and-lifecycle.md) | flock、关窗/小窗/托盘、二次启动、退出与崩溃 |
| [06-build-release](docs/06-build-release.md) | 工具链、构建、签名、CI、AGPL |
| [07-roadmap](docs/07-roadmap.md) | 阶段拆分、验收标准、估算 |
| [08-risks](docs/08-risks.md) | 风险清单与缓解、go/no-go 检查点 |
| [09-evaluation](docs/09-evaluation.md) | Wails / Flutter / 纯 Dart 的对比与结论 |
| [10-windows](docs/10-windows.md) | Windows P7：构建、SMTC、托盘/小窗、安装、CI |
| [11-macos](docs/11-macos.md) | macOS P1：非沙盒、audio_service、公证、DMG、CI |
| [12-development-environment](docs/12-development-environment.md) | 本机 Flutter、Android SDK、JDK 配置与实测结果 |
| [13-product-and-interaction](docs/13-product-and-interaction.md) | 桌面／移动端两套交互、页面、状态与常用快捷键 |
| [14-implementation-plan](docs/14-implementation-plan.md) | D0–D5 实施清单、依赖关系与联合发布门槛 |
| [17-full-gui-parity](docs/17-full-gui-parity.md) | 本轮功能矩阵、自动检查和设备验收状态 |
| [18-android-device-validation](docs/18-android-device-validation.md) | Android 16 扫描／出声／歌词验收、后台连接与 SAF 修复、设备待验证项目 |
| [15-design-preview](docs/15-design-preview.md) | 十三张 SVG 画板、四套配色与预览入口 |
| [设计预览](design/index.html) / [设计规范](design/README.md) | 离线切换桌面与移动端画板、共享视觉 token |
| [Dart 数据契约](packages/zero_beat_core/README.md) | 扩展 DTO、生成与校验、与当前 core 的对应边界 |
| [decisions/](docs/decisions/) | ADR-0001 ~ ADR-0009 |
| [迁移指南](../docs/monorepo-and-sync.md) | 模块布局、版本标签、双 Git 后端 |
| [TUI 架构](../ARCHITECTURE.md) | 现有 TUI 的分层与模块清单 |
| [IMPORT.md](IMPORT.md) | 从原 GUI 仓库导入的来源记录 |

## 复用边界

| 通过 `session` 复用（Go） | 重写（Flutter/Dart） | 平台迁移 |
| --- | --- | --- |
| `store`（SQLite、迁移、队列持久化） | 全部 UI 与导航 | 数据目录（Android 沙盒 / macOS `~/Library/Application Support` / Windows `%APPDATA%`） |
| `app`（搜索、解析、歌词、歌单、登录、下载） | 播放引擎（media_kit） | `sync`：git CLI / go-git 双后端 |
| `source` / `source/bilibili` / `netease` | Android 通知/锁屏（audio_service） | 下载完成处理器：桌面 ffmpeg / Android libav |
| `player.Controller`（队列、模式、预取、重试） | 桌面托盘、小窗、窗口管理 | 本地文件夹歌单（Android SAF） |
| `sync` / `library` / `lyrics` | 设置、主题、GUI 常用快捷键、登录二维码展示 | MPRIS（Linux）/ SMTC（Windows）/ Now Playing（macOS） |
| `sysmedia`（Linux MPRIS）、`instance`（flock / LockFileEx） | macOS 非沙盒 entitlement 与公证 | macOS 关闭沙盒 |

## 本地测试与当前边界

运行 `source zero-beat-gui/tool/dev-env.sh` 后在集成仓库执行 `make gui-linux` / `make gui-android`。Linux 使用自绘窗口和常用快捷键；关闭默认转后台，有实际托盘宿主才隐藏，否则最小化。移动端使用三个独立返回栈。运行步骤及隔离数据方法见[应用说明](app/README.md)。

Android arm64 构建先校验固定 FFmpeg 源码，再构建原生封装库和 Go 核心，最后验证 APK 的依赖闭包与 16KB 对齐。当前不生成发布标签或正式发布。macOS、Windows 构建与设备验收不在本轮完成范围。

## 许可

与 zero-beat 一致：[AGPL-3.0](LICENSE)。Go 核心以 c-shared（Linux/Android/macOS）或 sidecar（Windows）形式随 App 分发，整个应用按 AGPL 发布；不分发闭源构建。

本项目仅供学习、研究与技术交流，不用于商业用途。B 站与网易云音乐的音频、封面、商标等内容版权归对应平台及权利人所有。
