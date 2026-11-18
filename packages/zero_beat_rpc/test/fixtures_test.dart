import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zero_beat_rpc/engine_host.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

void main() {
  final root = Directory.current.path.endsWith('zero_beat_rpc')
      ? Directory.current.parent.parent
      : Directory.current;

  Map<String, Object?> load(String name) {
    final file = File('${root.path}/testdata/rpc/$name');
    final decoded = jsonDecode(file.readAsStringSync());
    return (decoded as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  test('hello and playback samples decode', () {
    final hello = load('core.hello.json');
    final result = HelloResult.fromJson(
      (hello['result'] as Map).map((k, v) => MapEntry(k.toString(), v)),
    );
    expect(result.api, rpcApiVersion);
    expect(result.player.snapshot.state.value, 'idle');
    expect(result.capabilities, contains('player'));
    expect(result.loudnorm, isFalse);

    final songs = load('library.songs.json');
    final page = SongPage.fromJson(
      (songs['result'] as Map).map((k, v) => MapEntry(k.toString(), v)),
    );
    expect(page.songs.single.title.length, greaterThan(20));

    final search = load('search.query.json');
    final hits = SearchView.fromJson(
      (search['result'] as Map).map((k, v) => MapEntry(k.toString(), v)),
    );
    expect(hits.hasWarning, isTrue);
    expect(hits.warning, contains('部分音源'));

    final link = load('source.open_link.json');
    final opened = LinkView.fromJson(
      (link['result'] as Map).map((k, v) => MapEntry(k.toString(), v)),
    );
    expect(opened.kind, 'track');
    expect(opened.song?.id, 'bilibili:BV1GJ411x7h7:2');
  });

  test('engine load keeps credentials out of the presentation model', () {
    final raw = load('engine.load.json');
    final params = (raw['request'] as Map)['params'] as Map;
    final loadRequest = EngineLoad.fromJson(
      params.map((k, v) => MapEntry(k.toString(), v)),
    );
    expect(loadRequest.playbackId, 'pb_01');
    expect(loadRequest.playWhenReady, isFalse);
    expect(loadRequest.stream.headers['Referer'], contains('bilibili'));
    expect(loadRequest.startAtMs, 15000);
  });

  test('error samples use the shared codes', () {
    final errors = load('errors.json');
    final stale = RpcMessage.parseLine(jsonEncode(errors['stale_playback']));
    expect(stale.error?.code, RpcCode.stalePlayback);
    final version = RpcMessage.parseLine(jsonEncode(errors['version']));
    expect(version.error?.code, RpcCode.version);
  });
}
