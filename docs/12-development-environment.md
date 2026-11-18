# 本地 Android 与 Flutter 开发环境

本页记录 **2026-11-17、Debian 13 x86_64** 的实际配置结果。环境已具备 Flutter/Dart、Linux 编译链及 Android SDK/NDK；Linux 最小工程已构建成功，Android 最小 APK 构建仍需完成网络修复后的复验。本页保留当时环境检查，后续应用构建结果见[完整功能验收](17-full-gui-parity.md)，工具链验收不等于产品验收。

## 已选工具链

| 组件 | 本机选择 | 路径 / 备注 |
| --- | --- | --- |
| Flutter | stable **3.41.2** | `$HOME/develop/flutter`，revision `90673a4eef275d1a6692c26ac80d6d746d41a73a` |
| Dart | **3.11.0** | 随上述 Flutter；纯 Dart 可直接使用 `bin/cache/dart-sdk/bin/dart` |
| Java | Android Studio JBR **21.0.9** | `$HOME/develop/android-studio/jbr` |
| Android SDK | compile / target **36** | `$HOME/develop/android-sdk` |
| Build Tools | **36.0.0** | `build-tools/36.0.0` |
| Platform Tools | **37.0.1** | 包含 adb |
| NDK | **28.2.13676358（r28c）** | `ndk/28.2.13676358` |
| Command-line Tools | **23.0** | `cmdline-tools/latest`；sdkmanager 转发 Android CLI **1.1.16919734** |
| Android minSdk | **24** | 与 Flutter 3.41.2 生成模板一致，旧设计 minSdk 23 不再作为当前基线 |
| Gradle / AGP / Kotlin | **8.14 / 8.11.1 / 2.2.20** | 临时工程模板实际生成版本；正式 App 创建时提交 wrapper 与版本声明 |
| Linux 编译链 | clang 19.1.7、CMake 3.31.6、Ninja 1.12.1 | GTK 3.24.49、liblzma 5.8.1、Ayatana AppIndicator 0.5.94 |

这是已经验证的版本组合，并非自动跟随 latest。未升级已有 Flutter；另一个 `$HOME/flutter` 中的 3.24.5 不作为本项目工具链。系统 Java 25 保持原样，项目通过 `JAVA_HOME` 选 JBR 21。Linux 已有 `libmpv.so.2` 运行库；未安装 `mpv.pc` 开发包，后续若插件构建需要它再补充。

## 启用环境

在集成仓库根运行：

```sh
source zero-beat-gui/tool/dev-env.sh
flutter --version
dart --version
java -version
adb version
bash zero-beat-gui/tool/check-dev-env.sh
```

脚本同时支持 bash 和 zsh，可重复 source。它仅修改当前 shell 环境，不写入 `.zshrc` / `.bashrc`，也不修改 Flutter 全局配置。新的 SDK 安装在用户可写目录，不覆盖系统 `/usr/lib/android-sdk` 中原有 adb。

其他机器先设置 `ZERO_FLUTTER_ROOT`、`ZERO_ANDROID_HOME`、`ZERO_JAVA_HOME` 再 source；默认路径适用于本次机器。`ZERO_GRADLE_USER_HOME` 可覆盖专用 Gradle 缓存位置。脚本会暴露 `ANDROID_NDK_HOME`，Go 编译时仍须按目标 ABI 明确选择 `CC`。

## 安装来源与复现

Android Command-line Tools 下载自 Google 官方仓库：

- 元数据：<https://dl.google.com/android/repository/repository2-3.xml>。
- 包：`commandlinetools-linux-16111833_latest.zip`，181,052,239 字节。
- 官方元数据 SHA-1：`e025545c62a8e64c7559119566a569fb1dec5f60`，下载后已核对。
- 本地 SHA-256：`0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8`。

配置 JBR 21 与 SDK 路径后，所需包为：

```sh
sdkmanager --sdk_root="$ANDROID_HOME" \
  'platform-tools' 'platforms;android-36' \
  'build-tools;36.0.0' 'ndk;28.2.13676358'
```

最新 Command-line Tools 23 的行为与旧版不同：`sdkmanager` 已是 Android CLI 兼容入口，`--licenses` 输出 “The --licenses option is no longer needed.”。本次安装没有传入自动接受参数、没有回答 `y`、也没有手写许可 hash；官方安装器自行创建了 `licenses/android-sdk-license`。需要审阅 SDK 适用条款时，以 [Android SDK 条款](https://developer.android.com/studio/terms) 为准；工具生成的文件不代表人工审阅记录。

Flutter 3.41.2 的 `doctor` 仍匹配旧版 sdkmanager 的 `All SDK package licenses accepted.` 字符串，因此目前显示 **Android license status unknown**。平台、构建工具、NDK 和 JDK 均已识别。没有修改 Flutter 检测代码或伪造检测输出；后续升级 Flutter 时重新验证这项兼容性。

## Maven Central 网络修复

本机访问 `repo.maven.apache.org` 与 `repo1.maven.org` 的 Kotlin POM 返回 HTTP 403；Google 的官方 Maven Central 镜像返回 200。第一次 Android debug 构建因此在 Gradle 解析阶段失败。

可选脚本 [dev-env-maven.init.gradle](../tool/dev-env-maven.init.gradle) 仅将 Maven Central 域名替换为 `https://maven-central.storage-download.googleapis.com/maven2`，保留 Google Maven、Gradle Plugin Portal 和 Flutter 下载地址；遵守 included build 的 settings repositories 策略。它受 `ZERO_BEAT_MAVEN_CENTRAL_MIRROR` 控制，支持设为空字符串关闭，不允许静默换用任意镜像。

本机已将该文件链接到项目专用缓存 `$HOME/develop/zero-beat-gradle/init.d/zero-beat-maven.gradle`。正式应用的 `make gui-android` 会通过仓库脚本安装或更新这个专用链接，并拒绝覆盖内容不同的普通配置文件。若只单独构建其他临时工程，可手动执行：

```sh
source zero-beat-gui/tool/dev-env.sh
mkdir -p "$GRADLE_USER_HOME/init.d"
# 从集成仓库根运行；目标文件已存在时先检查，不覆盖其他配置。
ln -s "$PWD/zero-beat-gui/tool/dev-env-maven.init.gradle" \
  "$GRADLE_USER_HOME/init.d/zero-beat-maven.gradle"
```

此配置不写入用户全局 `~/.gradle`，也不提交第三方镜像到未来 App 的 Gradle 项目配置。缓存专用于本项目；仓库移动后须更新该链接。修正脚本后的正式 APK 构建已实际复验：Plugin Portal 解析恢复，后续在 Kotlin／media_kit 原生依赖下载时遇到 TLS 握手失败，仍未生成 APK。详见[最新 GUI 验收记录](16-first-gui-validation.md)。

## 前置工具链验证与边界

下表保留最初环境准备结果；正式应用的最新构建与回归以[首批验收记录](16-first-gui-validation.md)为准。

| 检查 | 结果 |
| --- | --- |
| Flutter / Dart 版本、JBR 21、adb、SDK 包清单 | 已通过 |
| `flutter doctor -v` Linux / 网络检查 | 已通过；Android 仅有上述 license status unknown 警告 |
| 临时 Flutter Linux debug 构建 | 已通过；产物在 `/tmp/zero-flutter-dev-env-smoke/build/linux/x64/debug/bundle/` |
| 临时 Flutter Android debug APK | 未通过：最初 Maven Central 403；镜像脚本修正后的运行被自动审批服务 HTTP 429 阻止，命令未执行 |
| NDK Android arm64 共享库最小 C 编译 | 已通过；API 24，ELF LOAD 对齐 `0x4000`（16 KB） |
| env 脚本 bash / zsh 语法、重复 source | 已通过 |
| Android 模拟器 / 真机 | 未安装模拟器或系统镜像，本次未连接真机；不能验证安装、后台播放或锁屏 |

测试工程是隔离的 Flutter 模板，放在 `/tmp/zero-flutter-dev-env-smoke`，不进入 GUI 源码。NDK 最小共享库也只验证编译器和链接选项，不覆盖最终 `libzero.so`、media_kit 的 `.so` 或 APK zipalign。正式 App 必须对最终产物重新验证 16 KB 页对齐。

Android 构建复验命令：

```sh
source zero-beat-gui/tool/dev-env.sh
cd /tmp/zero-flutter-dev-env-smoke
flutter build apk --debug
```

临时目录丢失时重新创建模板即可。进入 GUI 真机验收前，还须配置 USB 调试并让用户在设备上授权，完成 APK 安装、播放、切歌、锁屏与无 ffmpeg 离线下载测试；这些不能用本页的工具链检查代替。
