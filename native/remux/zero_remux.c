// LGPL FFmpeg is statically linked into this narrowly scoped JNI-free library.
// No decoding/transcoding or external executable is involved in remuxing.
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

static int interrupted(void *opaque) {
  return atomic_load((const atomic_int *)opaque);
}
static int check_tags(AVDictionary *format, AVDictionary *stream,
                      const char *key, const char *expected) {
  if (!expected || !*expected) return 1;
  AVDictionaryEntry *tag = av_dict_get(format, key, NULL, 0);
  if (!tag) tag = av_dict_get(stream, key, NULL, 0);
  return tag && strcmp(tag->value, expected) == 0;
}
__attribute__((visibility("default")))
int zero_remux(const char *input, const char *output, const char *title,
               const char *artist, const char *album, const atomic_int *cancel,
               char *message, size_t capacity) {
  AVFormatContext *in = avformat_alloc_context(), *out = NULL, *verify = NULL;
  AVPacket *packet = av_packet_alloc();
  int result = AVERROR(ENOMEM), audio = -1, count = 0;
  enum AVCodecID codec = AV_CODEC_ID_NONE;
  if (!in || !packet) goto cleanup;
  in->interrupt_callback = (AVIOInterruptCB){interrupted, (void *)cancel};
  if ((result = avformat_open_input(&in, input, NULL, NULL)) < 0) goto cleanup;
  if ((result = avformat_find_stream_info(in, NULL)) < 0) goto cleanup;
  audio = av_find_best_stream(in, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
  if (audio < 0) { result = audio; goto cleanup; }
  codec = in->streams[audio]->codecpar->codec_id;
  if ((result = avformat_alloc_output_context2(&out, NULL, NULL, output)) < 0 || !out) goto cleanup;
  out->interrupt_callback = in->interrupt_callback;
  AVStream *stream = avformat_new_stream(out, NULL);
  if (!stream) { result = AVERROR(ENOMEM); goto cleanup; }
  if ((result = avcodec_parameters_copy(stream->codecpar, in->streams[audio]->codecpar)) < 0) goto cleanup;
  stream->codecpar->codec_tag = 0;
  stream->time_base = in->streams[audio]->time_base;
  if (*title) av_dict_set(&out->metadata, "title", title, 0);
  if (*artist) av_dict_set(&out->metadata, "artist", artist, 0);
  if (*album) av_dict_set(&out->metadata, "album", album, 0);
  if (!(out->oformat->flags & AVFMT_NOFILE) &&
      (result = avio_open2(&out->pb, output, AVIO_FLAG_WRITE, &out->interrupt_callback, NULL)) < 0) goto cleanup;
  if ((result = avformat_write_header(out, NULL)) < 0) goto cleanup;
  while ((result = av_read_frame(in, packet)) >= 0) {
    if (atomic_load(cancel)) { result = AVERROR_EXIT; goto cleanup; }
    if (packet->stream_index == audio) {
      av_packet_rescale_ts(packet, in->streams[audio]->time_base, stream->time_base);
      packet->stream_index = stream->index;
      packet->pos = -1;
      result = av_interleaved_write_frame(out, packet);
      if (result < 0) goto cleanup;
      count++;
    }
    av_packet_unref(packet);
  }
  if (result != AVERROR_EOF || count == 0) { if (result == AVERROR_EOF) result = AVERROR_INVALIDDATA; goto cleanup; }
  if ((result = av_write_trailer(out)) < 0) goto cleanup;
  if (out->pb && (result = avio_closep(&out->pb)) < 0) goto cleanup;
  verify = avformat_alloc_context();
  if (!verify) { result = AVERROR(ENOMEM); goto cleanup; }
  verify->interrupt_callback = in->interrupt_callback;
  if ((result = avformat_open_input(&verify, output, NULL, NULL)) < 0) goto cleanup;
  if ((result = avformat_find_stream_info(verify, NULL)) < 0) goto cleanup;
  audio = av_find_best_stream(verify, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
  if (audio < 0 || verify->streams[audio]->codecpar->codec_id != codec ||
      !check_tags(verify->metadata, verify->streams[audio]->metadata, "title", title) ||
      !check_tags(verify->metadata, verify->streams[audio]->metadata, "artist", artist) ||
      !check_tags(verify->metadata, verify->streams[audio]->metadata, "album", album)) {
    result = AVERROR_INVALIDDATA; goto cleanup;
  }
  result = 0;
cleanup:
  if (result < 0 && capacity) av_strerror(result, message, capacity);
  av_packet_free(&packet);
  avformat_close_input(&verify);
  avformat_close_input(&in);
  if (out) {
    if (out->pb) avio_closep(&out->pb);
    avformat_free_context(out);
  }
  return result;
}
