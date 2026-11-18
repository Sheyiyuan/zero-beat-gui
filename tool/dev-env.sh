# Source this file from bash or zsh; it does not edit your shell configuration.
# Override ZERO_FLUTTER_ROOT, ZERO_ANDROID_HOME, or ZERO_JAVA_HOME when needed.
export FLUTTER_ROOT="${ZERO_FLUTTER_ROOT:-${FLUTTER_ROOT:-$HOME/develop/flutter}}"
export ANDROID_HOME="${ZERO_ANDROID_HOME:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/develop/android-sdk}}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
if [ -n "${ZERO_JAVA_HOME:-}" ]; then
    export JAVA_HOME="$ZERO_JAVA_HOME"
elif [ -x "$HOME/develop/android-studio/jbr/bin/java" ]; then
    export JAVA_HOME="$HOME/develop/android-studio/jbr"
elif [ -n "${JAVA_HOME:-}" ]; then
    export JAVA_HOME
fi
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export GRADLE_USER_HOME="${ZERO_GRADLE_USER_HOME:-$HOME/develop/zero-beat-gradle}"

_zero_dev_prepend_path() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
_zero_dev_prepend_path "$ANDROID_HOME/cmdline-tools/latest/bin"
_zero_dev_prepend_path "$ANDROID_HOME/platform-tools"
_zero_dev_prepend_path "$FLUTTER_ROOT/bin"
if [ -n "${JAVA_HOME:-}" ]; then
    _zero_dev_prepend_path "$JAVA_HOME/bin"
fi
export PATH
unset -f _zero_dev_prepend_path

# This is consumed only by dev-env-maven.init.gradle, if explicitly installed
# into the project-specific GRADLE_USER_HOME. Set it to empty to disable.
export ZERO_BEAT_MAVEN_CENTRAL_MIRROR="${ZERO_BEAT_MAVEN_CENTRAL_MIRROR-https://maven-central.storage-download.googleapis.com/maven2}"
