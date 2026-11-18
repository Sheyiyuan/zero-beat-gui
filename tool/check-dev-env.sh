#!/usr/bin/env bash
set -euo pipefail
tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$tool_dir/dev-env.sh"

printf 'Flutter SDK: %s\nAndroid SDK: %s\nJDK: %s\nNDK: %s\nGradle cache: %s\n' \
    "$FLUTTER_ROOT" "$ANDROID_HOME" "${JAVA_HOME:-<unset>}" "$ANDROID_NDK_HOME" "$GRADLE_USER_HOME"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" --version
java -version
"$ANDROID_HOME/platform-tools/adb" version
"$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" --version
for package in gtk+-3.0 liblzma ayatana-appindicator3-0.1; do
    printf '%s: ' "$package"
    pkg-config --modversion "$package"
done
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --list_installed
flutter doctor -v
