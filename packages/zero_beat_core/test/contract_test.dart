import 'dart:convert';
import 'dart:io';

import '../lib/zero_beat_core.dart';
import '../lib/engine_contract.dart';
import 'fixture_decoders.g.dart';

int _checks = 0;
void expect(bool condition, String reason) {
  _checks++;
  if (!condition) throw StateError(reason);
}

void rejects(void Function() action, String reason) {
  _checks++;
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected FormatException: $reason');
}

void immutable(void Function() action, String reason) {
  _checks++;
  try {
    action();
  } on UnsupportedError {
    return;
  }
  throw StateError('Expected immutable value: $reason');
}

Object? canonical(Object? value) {
  if (value is double && value.isFinite && value == value.truncateToDouble())
    return value.toInt();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) return value.map(canonical).toList();
  return value;
}

String normalized(Object? value) => jsonEncode(canonical(value));

void main() {
  final document =
      jsonDecode(File('test/fixtures/core.json').readAsStringSync())
          as Map<String, dynamic>;
  expect(document['schema_version'] == coreSchemaVersion, 'schema version');
  final fixtures = document['fixtures'] as List<dynamic>;
  final byName = <String, Map<String, Object?>>{};
  for (final raw in fixtures) {
    final fixture = raw as Map<String, dynamic>;
    final value = Map<String, Object?>.from(fixture['value'] as Map);
    byName[fixture['name'] as String] = value;
    final output = roundTripFixture(fixture['type'] as String, value);
    expect(
      normalized(output) == normalized(value),
      'Go → Dart → JSON parity: ${fixture['name']}',
    );
  }

  final track = Track.fromJson(byName['program-track']!);
  expect(track.id == 'netease:program:2066770638:1', 'program stable key');
  expect(track.externalId == 'program:2066770638', 'do not replace program ID');
  expect(track.durationMs == 245000, 'seconds become milliseconds once');
  expect(track.cid == BigInt.parse('9223372036854775807'), 'exact int64 CID');
  final comment = Comment.fromJson(byName['comment']!);
  expect(
    comment.likes == BigInt.parse('9223372036854775807'),
    'exact int64 likes',
  );
  expect(
    comment.createdAt!.toIso8601String() == '2026-11-17T00:09:10.123Z',
    'UTC conversion, milliseconds truncated in Go',
  );
  final song = Song.fromJson(byName['legacy-song']!);
  expect(
    song.remoteId == 'BV1example' && song.page == 1,
    'legacy BVID normalization',
  );
  final player = PlaybackSnapshot.fromJson(byName['player']!);
  expect(
    player.positionMs == 1234,
    'duration nanoseconds are not passed as ms',
  );
  expect(player.state == PlaybackStatus.valuePaused, 'playback state mapping');
  expect(player.mode == PlaybackMode.valueShuffle, 'playback mode mapping');
  expect(player.quality == Quality.valueLossless, 'quality mapping');
  final empty = PlaybackSnapshot.fromJson(byName['idle-player']!);
  expect(
    empty.current == null && empty.sleepUntil == null && empty.queue.isEmpty,
    'nullable object/time and empty arrays',
  );
  final future = PlaybackSnapshot.fromJson(byName['future-player']!);
  expect(
    !future.state.isKnown && future.state.value == 'unknown:99',
    'unknown numeric enum preserved as opaque value',
  );
  final futureTrack = Track.fromJson({
    ...byName['program-track']!,
    'source': 'future-source',
  });
  expect(
    !futureTrack.source.isKnown &&
        futureTrack.toJson()['source'] == 'future-source',
    'unknown source string preserved',
  );
  final futureBrowse = BrowseRef.fromJson({
    ...byName['radio-ref']!,
    'kind': 'future-kind',
  });
  expect(
    !futureBrowse.kind.isKnown,
    'future browse kind does not break decoding',
  );
  final caps = SourceCapabilities.fromJson(
    byName['all-capabilities-and-future-bit']!,
  );
  expect(
    caps.names.contains(SourceCapability.browse) &&
        caps.names.contains(SourceCapability.comments),
    'optional source capabilities',
  );
  expect(
    caps.unknownBits == BigInt.from(2147483648),
    'unknown capability bits retained',
  );

  final unknownFields = Song.fromJson({
    ...byName['legacy-song']!,
    'future_field': {'x': 1},
  });
  expect(
    !unknownFields.toJson().containsKey('future_field'),
    'unknown fields safely ignored',
  );
  final missingNullable = {...byName['legacy-song']!}..remove('added_at');
  expect(
    Song.fromJson(missingNullable).addedAt == null,
    'missing nullable field',
  );
  final missingRequired = {...byName['legacy-song']!}..remove('id');
  rejects(() => Song.fromJson(missingRequired), 'missing id');
  rejects(
    () => Song.fromJson({...byName['legacy-song']!, 'id': null}),
    'null required field',
  );
  rejects(
    () => Song.fromJson({...byName['legacy-song']!, 'duration_ms': 123.5}),
    'fractional ms',
  );
  rejects(
    () => Song.fromJson({...byName['legacy-song']!, 'duration_ms': '123'}),
    'string ms',
  );
  rejects(
    () => Song.fromJson({
      ...byName['legacy-song']!,
      'duration_ms': 9007199254740992,
    }),
    'unsafe JSON integer',
  );
  rejects(
    () => Song.fromJson({...byName['legacy-song']!, 'cid': 42}),
    'numeric int64 ID',
  );
  rejects(
    () => Song.fromJson({
      ...byName['legacy-song']!,
      'cid': '9223372036854775808',
    }),
    'overflow int64',
  );
  rejects(
    () => Song.fromJson({...byName['legacy-song']!, 'cid': '01'}),
    'noncanonical integer',
  );
  expect(
    Song.fromJson({
          ...byName['legacy-song']!,
          'cid': '-9223372036854775808',
        }).cid ==
        -(BigInt.one << 63),
    'minimum signed int64',
  );
  rejects(
    () => Song.fromJson({
      ...byName['legacy-song']!,
      'added_at': '2026-02-31T00:00:00.000Z',
    }),
    'impossible date',
  );
  rejects(
    () => Song.fromJson({
      ...byName['legacy-song']!,
      'added_at': '2026-11-17T00:00:00',
    }),
    'timezone required',
  );
  rejects(
    () => Song.fromJson({
      ...byName['legacy-song']!,
      'added_at': '2026-11-17T00:00:00.123456Z',
    }),
    'sub-ms timestamp not silently rounded',
  );
  rejects(() => RelatedPage.fromJson({'candidates': null}), 'null array');
  rejects(
    () => RelatedPage.fromJson({
      'candidates': [true],
    }),
    'non-object item',
  );
  rejects(
    () =>
        PlaybackSnapshot.fromJson({...byName['player']!, 'volume': double.nan}),
    'nonfinite volume',
  );
  rejects(
    () => BrowseEntry.fromJson({...byName['radio-entry']!, 'ref': null}),
    'missing browse target',
  );
  rejects(
    () => BrowseEntry.fromJson({
      ...byName['radio-entry']!,
      'track': byName['program-track'],
    }),
    'mutually exclusive browse refs',
  );
  final radio = BrowseEntry.fromJson(byName['radio-entry']!);
  final program = BrowseEntry.fromJson(byName['program-entry']!);
  expect(
    radio.ref!.kind == BrowseKind.valueRadio && radio.track == null,
    'radio is not playable',
  );
  expect(
    program.ref == null && program.track!.externalId.startsWith('program:'),
    'program is playable',
  );

  final list = <String>['song-1'];
  final queue = QueueSnapshot(ids: list, index: 0, positionMs: 0);
  list.add('song-2');
  expect(queue.ids.length == 1, 'constructor copies mutable lists');
  immutable(() => queue.ids.add('song-3'), 'queue ids');
  immutable(() => caps.names.add('future'), 'capability names');
  final engine = EngineStream.fromJson(byName['engine-stream']!);
  expect(
    engine.headers['Referer'] == 'https://www.bilibili.com/',
    'engine header fidelity',
  );
  immutable(() => engine.headers['Cookie'] = 'secret', 'engine headers');
  expect(
    !StreamInfo.fromJson(
      byName['stream-info']!,
    ).toJson().containsKey('headers'),
    'presentation stream excludes headers',
  );
  final sync = SyncConfig.fromJson(byName['sync-config']!);
  expect(
    !sync.syncAccounts &&
        sync.remote == 'https://example.invalid/owner/repo.git',
    'account sync opt-in and credentials stripped',
  );
  final status = SyncStatus.fromJson(byName['sync-status']!);
  expect(status.hasError && status.warningCount == 1, 'safe sync diagnostics');
  expect(
    !normalized(status.toJson()).contains('secret'),
    'raw diagnostics never reach UI',
  );

  stdout.writeln(
    'Passed $_checks checks; ${fixtures.length} Go-generated parity fixtures.',
  );
}
