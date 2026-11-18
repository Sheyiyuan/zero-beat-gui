#!/usr/bin/env bash
# Execute the Android wrapper's exact C source on Linux; device tests stay separate.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
gui_dir="$(dirname -- "$script_dir")"
work="$gui_dir/build/remux-host"
mkdir -p "$work/source"
(cd "$gui_dir/build/sources" && sha256sum -c "$gui_dir/native/remux/ffmpeg-7.1.1.sha256")
tar -xf "$gui_dir/build/sources/ffmpeg-7.1.1.tar.xz" --strip-components=1 -C "$work/source"
cd "$work/source"
./configure --enable-pic --disable-shared --enable-static --disable-programs --disable-doc --disable-debug \
 --disable-x86asm --disable-network --disable-autodetect --disable-everything \
 --disable-avdevice --disable-avfilter --disable-swscale --disable-swresample --enable-avformat --enable-avcodec --enable-avutil \
 --enable-protocol=file --enable-demuxer=mov,mp3,flac,ogg,aac,wav,matroska \
 --enable-muxer=ipod,mp3,flac,ogg,opus --enable-parser=aac,mpegaudio,flac,opus,vorbis \
 --enable-decoder=aac,mp3,flac,opus,vorbis --disable-gpl --disable-nonfree --disable-version3 \
 --extra-cflags='-O2 -fPIC'
make -j"${ZERO_BUILD_JOBS:-4}"
cc -shared -std=c11 -O2 -fPIC -fvisibility=hidden -I. "$gui_dir/native/remux/zero_remux.c" \
 -Wl,--start-group libavformat/libavformat.a libavcodec/libavcodec.a libavutil/libavutil.a -Wl,--end-group \
 -Wl,--exclude-libs,ALL -lm -ldl -pthread -o "$work/libzeroremux.so"
python3 "$gui_dir/scripts/test-native-remux.py" "$work/libzeroremux.so" "$work/fixtures"
