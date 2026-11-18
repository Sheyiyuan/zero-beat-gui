# 零拍 Flutter 客户端

Linux 桌面与 Android 手机分别设计页面，共用 Go Session、Dart RPC 和播放状态。当前接入账号、歌单编辑／批量、搜索、歌词／片段、内容浏览、下载、同步和设置。0.8.0 尚未发布。

从集成仓库根目录运行：

```sh
source zero-beat-gui/tool/dev-env.sh
make check-gui
make gui-linux
./zero-beat-gui/app/build/linux/x64/debug/bundle/zero_beat_gui
make gui-android
```

Linux bundle 包含 `lib/libzero.so`；Android 调试包位于 `app/build/app/outputs/flutter-apk/app-debug.apk`，当前构建目标为 arm64，使用项目专用 Gradle 缓存。启动脚本将仓库中的 Maven 初始化脚本链接到该缓存，不修改全局 Gradle 配置。`ZERO_BEAT_MAVEN_CENTRAL_MIRROR=''` 可关闭镜像替换。

桌面使用已有 zero-beat 数据目录和实例锁；Android 使用应用沙箱目录。队列恢复后不会自动播放。桌面使用自绘边框，默认关闭后由托盘恢复；无托盘宿主时最小化，设置可改为迷你播放器或退出；手机后台播放不依赖页面继续显示。

桌面常用快捷键包括空格播放／暂停、Ctrl+F 搜索、Ctrl+左右切歌；输入框获得焦点时不抢占编辑按键。手机从歌单列表进入曲目页，系统返回回到歌单列表。歌单每批加载 200 首，搜索按核心返回页数翻页。

连接丢失会停止旧播放并显示“重新连接”。重连刷新快照和列表，保留核心队列，不自动播放或重放未确认操作。“我的”使用当前握手信息。Android 播放前请求音频焦点；失焦、拔耳机及人工暂停不会触发音源重试。

Android 核心通信使用应用私有 Unix socket，避免系统选择器／后台空闲网络限制中断本机控制连接。2026-11-18 已在 Android 16 真机验证目录扫描、冷启动后授权读取、实际出声、旁挂翻译歌词、暂停时歌词跳转和短时后台媒体控制；完整进展与当前响度均衡限制见[Android 真机验收](../docs/18-android-device-validation.md)。设备页大小为 4KB，APK 的 16KB 对齐检查通过不代表 16KB 运行时已验证。

SAF 音频通过 ContentResolver 读取并暂存为私有可 seek 文件，核心仍保存 URI 身份。关闭资源句柄时清除缓存，进程重启后清理遗留文件；打开大文件需要额外空间和复制时间。Android 存储缓存回归从集成仓库根目录运行：

```sh
source zero-beat-gui/tool/dev-env.sh
cd zero-beat-gui/app/android
./gradlew :app:testDebugUnitTest -Ptarget-platform=android-arm64
```

真实动态库回归（先执行 `make gui-linux`）：

```sh
cd zero-beat-gui/packages/zero_beat_rpc
LD_LIBRARY_PATH="$PWD/../../build" ZERO_BEAT_NATIVE_TEST=1 dart test test/native_integration_test.dart
```

测试使用临时数据目录。具体已通过项目、平台限制和待验证项见[完整验收记录](../docs/17-full-gui-parity.md)。

## 隔离 Linux 播放验收

不要对正在使用的 TUI／GUI 数据目录运行自动操作。集成测试会创建短测试音，验证真实 media_kit／Go、MPRIS、暂停 seek 和断线重连，并输出截图：

```sh
cd zero-beat-gui/app
export XDG_CONFIG_HOME="$(mktemp -d /tmp/zero-gui-smoke-XXXXXX)"
export ZERO_MPRIS_NAME=org.mpris.MediaPlayer2.zero.smoketest
flutter test integration_test/linux_playback_test.dart -d linux --reporter expanded
```

测试保存的 `linux-library.png`、`pulse-sink-inputs.txt`、`result.txt` 位于该隔离目录。TUI／GUI 同步互通可运行 `bash ../scripts/test-native-interop.sh test/tui_interop_test.dart`，脚本使用 go-git 后端和独立临时数据。音频流存在与位置推进不等于人工听音确认。Android 实机仍需后台／锁屏 30 分钟、通知、耳机／焦点竞争、SAF 权限撤销与导出验证。

Android 的 `make gui-android` 需要固定且验证过的 FFmpeg 源码，准备方式见[原生组件说明](../native/remux/README.md)。普通下载先保存到私有目录，菜单区分“导出到系统音乐”和“另存到指定位置”，导出失败保留原文件。
