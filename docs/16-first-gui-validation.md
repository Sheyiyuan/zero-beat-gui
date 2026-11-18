# GUI 首批修复与验收记录

> 历史记录：以下描述 2026-11-17 的结果；最新实现、构建及未完成项以[完整功能验收](17-full-gui-parity.md)为准。

本记录针对 2026-11-17 工作区中的首批 GUI。core / TUI 0.8.0 保持未发布；GUI 为开发版本。

## 修复内容

- 播放意图随暂停／恢复更新，缓冲结束和暂停中的 seek 使用最新意图。
- load 校验并接收后立即确认；实际媒体打开在后台进行，始终先以暂停模式打开。停止／换歌使旧代次失效，销毁旧播放器后才创建新实例，迟到回调不再改变当前曲目。
- 原生启动与 Socket 连接分离；连接状态主动通知界面；断线手动重连不会重复 ZeroStart，不重放播放命令。失败回滚释放本运行时持有的资源，“我的”读取握手缓存。
- Android 音频焦点由统一协调器管理，拒绝焦点保持暂停并提示；临时中断只在用户未干预时续播，永久失焦及拔耳机不自动恢复。音频服务在重连时重新绑定 API。
- Gradle 镜像脚本保留 Plugin Portal / Google 仓库，Android 构建入口自动使用仓库脚本。
- 桌面歌单点击退出搜索并丢弃旧搜索响应；手机独立歌单列表／详情；歌单请求隔离过期响应，提供每批 200 首追加，搜索提供页码和翻页重试。

## 可复现命令

在集成仓库根目录加载 `source zero-beat-gui/tool/dev-env.sh` 后执行：

```sh
make check-gui
go -C zero-beat-core test -race ./session
go -C zero-beat-gui test -race ./...
go -C zero-beat-gui vet ./...
(cd zero-beat-gui/app && flutter analyze --no-pub)
make check-docs
make gui-linux
make gui-android
```

真实动态库测试命令见[应用运行说明](../app/README.md)。所有测试使用临时目录，不修改现有曲库。

## 验证结果

| 项目 | 本轮结果 |
| --- | --- |
| Go Session race | 通过 |
| GUI Go race / vet | 通过；新增断线清理完成前拒绝新控制连接的回归单独通过 |
| Dart RPC | 12 项通过；真实动态库集成测试默认跳过，显式运行见下方限制 |
| Dart 类型契约 | 93 项检查、45 份 Go 样本、生成漂移检查通过 |
| Flutter | 当前 30 项用例全部通过，包括播放、焦点、曲库分页、搜索、移动导航和断线界面 |
| App / RPC 静态分析 | 通过 |
| 文档链接 / 空白检查 | 293 个本地链接通过；diff 空白检查通过 |
| Linux debug bundle | 当前源代码重新构建成功，包含 libzero.so |
| Android arm64 libzero.so | 构建通过，LOAD 段对齐 0x4000 |
| Android debug APK | 未生成：Plugin Portal 问题已解决；后续依赖下载遇到 TLS 握手失败 |
| Linux 实际音频输出 | 待验收：沙箱内 PulseAudio 返回 Operation not permitted，已停止测试进程 |
| Android 安装／后台／通知／焦点竞争 | 未验证；本轮设备枚举也未完成 |

自动审批服务返回 HTTP 429，阻止了常规 Flutter 复测、真实动态库联调和设备检查的后续提升权限命令。这是审批服务错误，不是测试失败。为完成可在沙箱内进行的检查，本轮使用只读 SDK 编译到 `/tmp`、关闭 VM 调试服务的 `flutter_tester` 和 `test_api` 执行仓库全部 30 项原始用例，结果为 30 通过、0 失败；另用真实 PlaybackHost 和假播放器验证慢打开、停止／切换、代次隔离与焦点拒绝。没有放宽沙箱或改写 SDK。

最终 Linux 构建使用 `/tmp/zero-beat-flutter-build-sdk` 的独立缓存元数据，工具与已有引擎文件只读复用已安装 SDK。依赖已就绪后运行 `flutter build linux --debug --no-pub` 成功；产物位于 `app/build/linux/x64/debug/bundle/zero_beat_gui`。

Android 首次下载 Kotlin 依赖时镜像 TLS 握手失败；Flutter 自动重试后推进到 media_kit 原生依赖，再在 `https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8/default-armeabi-v7a.jar` 下载阶段失败。插件会下载多个 ABI 的原生依赖，即使应用只打包 arm64。未禁用 TLS 校验或更换不受信任的下载来源。需网络恢复后再次运行 `make gui-android`，并检查最终 APK 内全部原生库及 zipalign。

真实动态库测试 `ZERO_BEAT_NATIVE_TEST=1` 尚待审批服务恢复后执行。代码测试与真实设备测试分别记录，不将构建通过视为后台播放通过。

## 设备验收项目

Linux 实际播放器：文件解码与位置推进、暂停、恢复、seek、切歌、退出和重连。Android：APK 安装、播放、退后台、通知与锁屏控制、竞争音频、临时／永久中断及拔耳机。没有可用设备时保留待验收，不能使用 FakePlayer 的结果替代。
