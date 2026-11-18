# 构建与发布

Linux 与 Android 开发产物已进入联合验收；core／TUI 0.8.0 继续不发布，不创建标签。本页前半是当前可执行入口，macOS／Windows 部分保留后续平台约定。

## 当前构建入口

在集成仓库根目录：

```sh
source zero-beat-gui/tool/dev-env.sh
make check-gui
make gui-linux
make gui-android
```

`gui-linux` 先构建当前 Go `cmd/lib`，再由 Flutter CMake 将 `libzero.so` 安装进 bundle。Linux 托盘插件在新 Ayatana 上的弃用警告保持可见，仅该插件不将弃用警告当作编译错误。

`gui-android` 使用 `scripts/build-apk.sh`：先校验固定 FFmpeg 7.1.1 源码并构建原生 `libzeroremux.so`，再以 NDK r28c/API 24 构建当前 Go 核心，最后构建 arm64 调试 APK。项目显式过滤插件 ABI，不依赖 Flutter target-platform 自动过滤。所有原生库必须通过 `scripts/check-apk.py` 的 AArch64、NEEDED 依赖闭包、ELF LOAD 16KB 与 zipalign 检查。

首次构建先按[原生组件说明](../native/remux/README.md)取得并验证源码。NDK、Flutter、Java、Gradle 配置只由 `tool/dev-env.sh` 的局部环境控制。Maven 初始化脚本保留 Plugin Portal、Google 和项目仓库，仅替换 Maven Central；`ZERO_BEAT_MAVEN_CENTRAL_MIRROR=''` 可关闭替换。

| 本地产物 | 路径（相对 GUI） |
| --- | --- |
| Linux bundle | `app/build/linux/x64/debug/bundle/zero_beat_gui` |
| Android arm64 APK | `app/build/app/outputs/flutter-apk/app-debug.apk` |
| Linux 核心 | `build/libzero.so` |
| Android 原生库 | `app/android/app/src/main/jniLibs/arm64-v8a/` |
| 原生可重链接输入 | `build/remux-arm64/relink/` |

运行及隔离曲库验收见[应用说明](../app/README.md)。实际通过状态见[完整功能验收](17-full-gui-parity.md)；历史首批报告不代表最新构建。

## 模块与入口

`zero-beat-core`、`zero-beat-tui`、`zero-beat-gui` 独立 module，由集成仓库 `go.work` 联调。GUI 只依赖公开 Session／业务包，不 import TUI internal。未发布 core 0.8.0 时，独立验证通过 `scripts/check-modules.py` 的临时本地代理进行，不能临时发布版本以满足构建。

c-shared 导出 `ZeroStart`、`ZeroStop`、`ZeroFree`。Dart 在工作 isolate 启动核心，复制结果并释放 C 内存；只有成功启动的运行时拥有关闭权。凭据只在内存，重新连接不重复启动核心，失败按逆序释放资源。

## 构建 Windows（P7）

```powershell
# 1) Go 核心：纯 Go，无 cgo，可在 Linux 交叉编译
$env:GOOS="windows"; $env:GOARCH="amd64"; $env:CGO_ENABLED="0"
go build -trimpath -ldflags "-s -w" -o app/windows/runner/zero-core.exe ./cmd/exe

# 2) Flutter Windows（必须在 Windows 上）
cd app
flutter build windows --release
```

- Flutter Windows 需要 Visual Studio 2022 的 C++ 桌面工作负载；Linux 不能交叉构建；
- 不用 Go DLL/MinGW：`zero-core.exe` 纯 Go，避免 cgo ABI 与运行库问题；
- `smtc_windows` 需要构建机有 rustup；CI 里显式安装；
- 安装包用 MSIX（`msix` 包）或 Inno Setup；代码签名可选；
- 下载功能依赖 ffmpeg：随包附带、检测系统 ffmpeg，或暂时禁用（[10-windows](10-windows.md)）。

## 构建 macOS（P1）

```bash
# 1) Go 核心：arm64（Intel 另编 amd64 后 lipo）
CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
  go build -buildmode=c-shared -o app/macos/Frameworks/libzero.dylib ./cmd/lib
install_name_tool -id @rpath/libzero.dylib app/macos/Frameworks/libzero.dylib

# 2) Flutter
(cd app && flutter build macos --release)

# 3) 签名、公证、装订
codesign --force --options runtime --sign "Developer ID Application: …" \
  app/build/macos/Build/Products/Release/zero-beat.app/Contents/Frameworks/libzero.dylib
codesign --force --options runtime --sign "Developer ID Application: …" \
  app/build/macos/Build/Products/Release/zero-beat.app
xcrun notarytool submit zero-beat.dmg --keychain-profile … --wait
xcrun stapler staple zero-beat.dmg
```

- Xcode 工程把 `libzero.dylib` 放进 **Frameworks and Libraries + Embed Frameworks**，rpath 指到 `@rpath`；
- **关闭 App Sandbox**（`macos/Runner/*.entitlements` 里 `com.apple.security.app-sandbox` = false），否则数据目录会被重定向到容器，无法与 TUI 共用；保留 Hardened Runtime；
- `macos/Podfile` 的 `platform :osx, '12.0'` 与最低版本一致；
- 关闭窗口隐藏而不是退出：`applicationShouldTerminateAfterLastWindowClosed` 返回 false，配合 `window_manager`；
- 通用包：分别编 `arm64`/`amd64` 的 dylib 后 `lipo -create`，Flutter App 也要按 universal 构建；
- 签名/公证需要 Apple Developer 账号；未公证的构建只适合本机自用；
- 下载依赖 ffmpeg：检测 Homebrew/系统 ffmpeg，没有时禁用下载。

## Flutter 依赖

| 依赖 | 用途 |
| --- | --- |
| `media_kit` + `media_kit_libs_*` | 播放（libmpv；Windows 也有对应 libs） |
| `audio_service` / `audio_session` | Android 通知、锁屏、焦点；macOS 的 Now Playing/控制中心 |
| `smtc_windows` | Windows SMTC（媒体键、系统媒体浮层） |
| `window_manager` / `tray_manager` | 桌面窗口与小窗、托盘 |
| `path_provider` | Android 数据目录 |
| `dart:io Socket` | 桌面 TCP／Android Unix socket NDJSON RPC，与 02-rpc 的传输约定一致；不使用 WebSocket 帧 |
| `flutter_riverpod` | 状态管理 |
| `dynamic_library` / `dart:ffi` | 加载 `libzero.so` / `libzero.dylib` 并调用 `ZeroStart`（Windows 不需要） |
| `local_notifier` | Windows 通知（可选） |

注意：插件最低 Flutter/Dart 版本在 P1 按实际选定版本核对并锁定。不引入 `flutter_ffmpeg`；各端播放不依赖 ffmpeg 可执行文件，桌面下载仍依赖它，Android 下载使用原生 libav 封装处理器。

## Android Manifest

- 权限：`INTERNET`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`、`WAKE_LOCK`；
- `audio_service` 的 Service/Receiver 声明；
- `android:launchMode="singleTask"`；
- `minSdk 24`、`targetSdk 36`；与本轮 Flutter 基线对齐。

## CI

| Job | 内容 |
| --- | --- |
| Linux | Go 单测 + Dart/RPC 契约测试 + Android APK/AAB + Linux AppImage/deb |
| macOS（P1） | `libzero.dylib` + Flutter macOS + 签名/公证 + DMG（需要证书与 Apple ID secrets） |
| Windows（P7） | Flutter Windows 构建 + `zero-core.exe`（Linux 交叉编或 Windows 编）+ MSIX |

- 缓存 Go module 与 Flutter SDK；
- P0 即加入核心依赖树/目标构建检查；Windows 的纯 Go 核心检查不代表提前交付 Flutter Windows；
- Session/RPC 回归覆盖旧结果、播放代次、终态去重、最多一次重试、双向调用和断线恢复；
- P5 加入 v2 字节样本、未知字段写前保护与双后端树/祖先/恢复测试；
- macOS job 用 `macos-14`/`macos-15`，安装 Xcode/CocoaPods；
- Windows job 需要 Visual Studio Build Tools、rustup（SMTC）；
- Android 模拟器冒烟（启动、列歌单、播放 30 秒）可选，先手动；
- Android 真机锁屏 30 分钟及无 ffmpeg 下载/离线验证为阶段必需验收，记录结果；模拟器冒烟不能替代它们；
- 不建 iOS job。

## 版本与兼容

- App 版本：语义化版本，独立于 zero-beat；
- 核心版本：随依赖的 zero-beat tag；
- `api`：RPC 协议版本，破坏性变更才升；
- `repo`：同步仓库版本，必须与 zero-beat 的 `meta.v` 对齐；
- 升级 zero-beat 依赖时，跑「同一仓库双端同步」集成测试。

首轮联合发布须完成 GUI 路线图的发布验收，并补跑 TUI 评论／推荐／主页／节目、桌面共享数据、默认关闭登录态同步及 v2/v3 仓库的双端回归。通过后再按 core → TUI → 集成仓库应用标签的依赖顺序发布，并同时提供 GUI 安装包；GUI Release 保持非 latest，避免抢占现有 TUI 安装脚本入口。

## 发布物

| 产物 | 内容 |
| --- | --- |
| Android APK/AAB | arm64-v8a（+ x86_64 可选） |
| Linux AppImage / deb | Flutter bundle + libzero.so + .desktop/图标 |
| macOS DMG（P1） | 签名/公证后的 .app + libzero.dylib |
| Windows MSIX / zip（P7） | Flutter bundle + zero-core.exe（+ 可选 ffmpeg） |
| 校验和 | SHA256 |
| 源码 | 本仓库 + 依赖的 zero-beat tag（AGPL 要求） |

## 许可证

AGPL-3.0。Go 核心以 c-shared（Linux/Android/macOS）或 sidecar（Windows）随 App 分发，整个应用按 AGPL 分发；「关于」页放源码链接与许可证。Android 商店（Play/F-Droid）与 AGPL 兼容；macOS 不走 Mac App Store（AGPL 与商店条款冲突），iOS 不在范围内。
