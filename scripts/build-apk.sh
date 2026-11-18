#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
gui_dir="$(dirname -- "$script_dir")"
source "$gui_dir/tool/dev-env.sh"
# Every APK is built from current native sources; do not package stale jniLibs.
"$gui_dir/scripts/build-android-remux.sh"
CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" \
CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
"$gui_dir/scripts/build-lib.sh" "$gui_dir/app/android/app/src/main/jniLibs/arm64-v8a/libzero.so"
mkdir -p "$GRADLE_USER_HOME/init.d"
init_link="$GRADLE_USER_HOME/init.d/zero-beat-maven.gradle"
if [[ -e "$init_link" && ! -L "$init_link" ]]; then
    if ! cmp -s "$gui_dir/tool/dev-env-maven.init.gradle" "$init_link"; then
        echo "Existing Gradle init file differs: $init_link" >&2
        exit 1
    fi
elif [[ -L "$init_link" ]] && [[ "$(basename -- "$(readlink -- "$init_link")")" != dev-env-maven.init.gradle ]]; then
    echo "Existing Gradle init link belongs to another configuration: $init_link" >&2
    exit 1
fi
ln -sfn "$gui_dir/tool/dev-env-maven.init.gradle" "$init_link"
cd "$gui_dir/app"
flutter build apk --debug --target-platform android-arm64

python3 "$gui_dir/scripts/check-apk.py" "$gui_dir/app/build/app/outputs/flutter-apk/app-debug.apk" \
  --readelf "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" \
  --zipalign "$ANDROID_HOME/build-tools/36.0.0/zipalign"
