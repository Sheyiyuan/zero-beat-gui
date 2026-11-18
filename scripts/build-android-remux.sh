#!/usr/bin/env bash
# Build only from an explicitly verified source archive; never silently use a
# moving branch or a binary downloaded from an unrelated distribution.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
gui_dir="$(dirname -- "$script_dir")"
source "$gui_dir/tool/dev-env.sh"
version=7.1.1
archive="${ZERO_FFMPEG_ARCHIVE:-$gui_dir/build/sources/ffmpeg-$version.tar.xz}"
checksum="$gui_dir/native/remux/ffmpeg-$version.sha256"
if [[ ! -f "$archive" || ! -f "$checksum" ]]; then
  echo "Verified FFmpeg $version source is required: $archive and $checksum" >&2
  exit 1
fi
expected="$(cut -d ' ' -f1 "$checksum")"
actual="$(sha256sum "$archive" | cut -d ' ' -f1)"
[[ "$actual" == "$expected" ]] || { echo "FFmpeg source checksum mismatch" >&2; exit 1; }
work="$gui_dir/build/remux-arm64"
mkdir -p "$work/source" "$work/install"
tar -xf "$archive" --strip-components=1 -C "$work/source"
ndk_bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
cd "$work/source"
./configure --prefix="$work/install" --target-os=android --arch=aarch64 --enable-cross-compile \
 --cc="$ndk_bin/aarch64-linux-android24-clang" --ar="$ndk_bin/llvm-ar" --ranlib="$ndk_bin/llvm-ranlib" --strip="$ndk_bin/llvm-strip" \
 --enable-pic --disable-shared --enable-static --disable-programs --disable-doc --disable-debug \
 --disable-network --disable-autodetect --disable-everything --disable-avdevice --disable-avfilter --disable-swscale --disable-swresample --enable-avformat --enable-avcodec --enable-avutil \
 --enable-protocol=file --enable-demuxer=mov,mp3,flac,ogg,aac,wav,matroska \
 --enable-muxer=ipod,mp3,flac,ogg,opus --enable-parser=aac,mpegaudio,flac,opus,vorbis \
 --enable-decoder=aac,mp3,flac,opus,vorbis \
 --disable-gpl --disable-nonfree --disable-version3 \
 --extra-cflags='-O2 -fPIC -ffile-prefix-map=.=.'
make -j"${ZERO_BUILD_JOBS:-4}"
make install
out="$gui_dir/app/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$out"
"$ndk_bin/aarch64-linux-android24-clang" -c -std=c11 -O2 -fPIC -fvisibility=hidden -I"$work/install/include" "$gui_dir/native/remux/zero_remux.c" -o "$work/zero_remux.o"
"$ndk_bin/aarch64-linux-android24-clang" -shared -std=c11 -O2 -fPIC -fvisibility=hidden \
 -I"$work/install/include" "$gui_dir/native/remux/zero_remux.c" \
 -Wl,--start-group "$work/install/lib/libavformat.a" "$work/install/lib/libavcodec.a" "$work/install/lib/libavutil.a" -Wl,--end-group \
 -lm -ldl -Wl,--exclude-libs,ALL -Wl,-z,max-page-size=16384 -Wl,-soname,libzeroremux.so -o "$out/libzeroremux.so"
"$ndk_bin/llvm-readelf" -lW "$out/libzeroremux.so"

# Retain the exact inputs required to rebuild/relink the LGPL component.
mkdir -p "$work/relink"
cp "$work/zero_remux.o" "$work/source/config.h" "$work/source/ffbuild/config.mak" "$work/relink/"
cp "$work/source/COPYING.LGPLv2.1" "$work/relink/"
cp "$work/install/lib/"*.a "$work/relink/"
sha256sum "$out/libzeroremux.so" > "$work/libzeroremux.sha256"
