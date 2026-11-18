# Android 真机验收记录

日期：2026-11-18。设备：Xiaomi 17 Pro（25098PN5AC），Android 16／API 36，arm64-v8a，内存页大小 4096 字节。本记录不等同于全部 Android 功能通过，也不能代替 16KB 页运行时验证。

## 已验证

- ADB 已授权，调试 APK 安装成功；普通入口冷启动成功，Flutter／media_kit 原生库加载成功。
- 曲库首屏正常；“我的”页显示已连接、核心 0.8.0 和账号摘要。
- 系统目录选择器可以打开，用户完成了独立 `Music/ZeroBeatAcceptance20261118` 测试目录的授权；未授权整个共享存储。修复后浅层扫描成功，收录 180 秒及 1 秒的两首 WAV；覆盖安装、强制停止及冷启动后，无需重新选择目录即可播放。
- 原版在系统选择器中停留后，返回应用两次出现连接断开，扫描失败；进程仍存活。手动重连成功，未自动起播。
- 同期系统日志显示应用 UID 进入空闲状态及 standby 防火墙 deny。Android IPC 已从回环 TCP 改为应用私有 `core.sock`；修复版安装、启动成功，真机确认 socket 权限为 `0600`。
- Unix socket 修复后，在系统选择器和后台停留超过一分钟，返回后扫描与播放可用，未再次重连。
- 授权 URI 的本地 WAV 已实际出声，用户明确确认“能听到”；媒体会话为 PLAYING，位置持续推进，前台音频服务和三项媒体通知动作存在。
- 同名旁挂原文与 `.zh.lrc` 翻译可显示；暂停在 117.750 秒后点选“Background playback”歌词，跳到 29.999 秒并保持 PAUSED。
- 系统媒体 play／pause 命令可恢复与暂停。退到桌面约 251 秒后仍为 PLAYING，再次暂停成功。这是短时后台验证，不计为 30 分钟锁屏验收，也不代表通知或锁屏触摸控制已验证。
- 最终包再次覆盖安装、冷启动，完成 PLAY → STOP → PLAY → PAUSE → PLAY → STOP：停止后媒体会话为空闲，私有缓存由 5,760,044 字节变为 0 个文件，音频焦点释放、服务退出前台；显式再次播放重新打开文件，暂停与恢复仍正常。测试结束已停止声音。

## 本次修复及自动验证

Android `ZeroStart` 增加 `socket_path`，`port` 为 0；Dart 保留启动凭据并用 Unix socket 重连。桌面保留原有 TCP。两种传输沿用 token 鉴权、单控制连接、断线停止和不重放写命令规则。关闭时删除 socket，启动时仅回收没有监听者的遗留 socket，不覆盖普通文件或活跃端点。

目录扫描另发现 ContentResolver 枚举成功但直接借用原始描述符检查音频失败，大小两个 WAV 均被跳过。没有捕获到能确定更底层原因的 errno；不能将 provider 代理或不可 seek 认定为实测根因。现由 ContentResolver 读取授权内容并暂存到应用私有普通文件，再把可 seek 的描述符交给核心／播放器。实际扫描与播放已恢复。持久身份仍为 URI，不推断共享存储路径。

临时文件随资源句柄关闭删除，进程重启后首次打开资源清理上次遗留文件；Activity 销毁不关闭仍归后台播放器所有的句柄。当前每次打开会完整暂存音频，额外磁盘空间及初次读取耗时与文件大小有关。超大文件、真实空间不足和 Activity 重建仍需设备验收。

本轮又发现系统媒体 stop 未转发到核心。新增 `player.stop`，调用现有 Session 停止逻辑，取消加载、隔离旧代次并保留队列。Android 停止时取消中断后的自动恢复、释放焦点；空闲快照退出音频服务的播放状态。暂停／停止同时退出前台服务状态，重新播放恢复前台。Session 的 resume／toggle 在停止后可重新加载保留的队列当前位置，暂停状态仍走恢复。

- Go RPC／runtime race、vet 通过：鉴权、活跃监听者保护、遗留 socket 清理、启动失败后重试。
- 最新 Session／RPC／runtime race、Session／GUI vet 通过；新增系统停止转发、保留队列及旧事件隔离回归。
- Dart RPC 共 15 项通过，含 Linux TCP 和 Android Unix 配置下的真实动态库启动、握手、stop、重连及关闭后重启；另 1 项 TUI／GUI 互通专项测试未在此轮重复运行。
- Dart RPC 分析与 Flutter 分析通过；Flutter 共 49 项通过，包含系统停止释放焦点、阻止中断续播、空闲媒体状态及停止后再次播放。
- Android `ResourceCacheTest` 4 项通过：未知长度／非 seek 流随机读取、provider 失败清理、分配失败关闭输入、重启遗留清理与当前文件保留。
- 最新代码 Linux debug bundle 和 Android arm64 debug APK 重建通过；APK 7 个原生库的 AArch64、依赖闭包、ELF／ZIP 16KB 对齐通过，已安装至本机复验。GUI RPC／runtime Windows 交叉编译为前一轮结果，本次未重复。

最终 APK：`app/build/app/outputs/flutter-apk/app-debug.apk`。SHA256：`b0ef756625aca582ddf19babb93e387254a0e2da6289af24a8e22ee15bb2d299`。Linux：`app/build/linux/x64/debug/bundle/zero_beat_gui`。两端均为本地调试产物，未创建标签或发布。

## 未通过／待验证

- Android 播放库当前没有 `loudnorm`／`alimiter` 滤镜；启动能力探测显示响度均衡不可用。不能将自动响度均衡计为 Android 已完成。
- 锁屏及后台至少 30 分钟、实际通知／锁屏触摸操作、耳机与音频竞争仍待设备验收。系统媒体命令不能替代这些操作。
- Activity 重建不中断播放、Android 本地歌词手动绑定、内嵌歌词和真实空间不足仍待设备验收。
- 授权撤销／恢复、目录移动、Android 原生封装与标签回读、MediaStore／指定位置导出及离线播放仍待设备验收。

用户已确认 USB 调试安全设置开启；ADB 点击仍偶有未生效，实际操作通过 UI dump／截图及媒体状态逐次核对，不按命令退出码判为通过。

本地证据保存于 `build/validation/evidence/android-20261118/`，构建和测试日志保存于 `build/validation/logs/`；这些包含设备调试数据的目录不参与发布。

关键证据：`lyrics-paused.png`（歌词与翻译），`background-media-state.txt`（短时后台），`final-media-and-cache.txt`（最终包播放／停止／恢复与缓存）。最新回归日志使用 `device-stop-*`、`android-resource-cache-tests.log`；构建日志为 `android-device-final-build.log`、`device-final-linux-build.log`。
