# Android 音频封装组件

`zero_remux.c` 导出 `zero_remux`，复制音频包并写入标题、艺人、专辑。Go Android 下载器用 dlopen 调用；没有 JNI 或外部进程。取消通过原子标志及 libav 中断回调传播。

## 源码与构建

在 GUI 目录执行：

```sh
mkdir -p build/sources
curl --fail --location https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz -o build/sources/ffmpeg-7.1.1.tar.xz
(cd build/sources && sha256sum -c ../../native/remux/ffmpeg-7.1.1.sha256)
./scripts/build-android-remux.sh
```

源码归属 FFmpeg，版本 7.1.1；本轮从官网取得源码、分离签名与发布密钥，gpgv 验证通过。预期 SHA256 由仓库固定，不从下载响应动态生成。构建要求 NDK 28.2.13676358；默认 API 24、arm64-v8a。所有编译参数位于构建脚本。`--exclude-libs,ALL` 隐藏静态依赖符号，避免与播放器中另一份 libav 发生符号抢占。

FFmpeg 仅启用 LGPL 组件，禁用 GPL／nonfree／version3、网络和外部自动依赖。LGPL v2.1 文本来自已验证源码；构建保留在 `build/remux-arm64/relink/`。发布时须随源码分发固定归档、构建脚本、封装源码及精确配置，并提供该目录的对象和静态库，便于替换组件并重新链接；当前不发布。

## 产物

- `app/android/app/src/main/jniLibs/arm64-v8a/libzeroremux.so`
- `build/remux-arm64/relink/zero_remux.o`、`libav*.a`、`config.h`、`config.mak`、`COPYING.LGPLv2.1`
- `build/remux-arm64/libzeroremux.sha256`

APK 入口统一使用 `scripts/build-apk.sh`，结束时运行 `scripts/check-apk.py` 验证 ABI、依赖闭包、导出函数、ELF LOAD 与 ZIP 的 16KB 对齐。不能把桌面 ffmpeg 测试当成此库的 Android 设备验证。
