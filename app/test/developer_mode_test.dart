import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/features/developer_mode.dart';

import 'support/memory_developer_mode_store.dart';

void main() {
  test('loads a persisted developer flag', () async {
    final store = MemoryDeveloperModeStore(true);
    final container = ProviderContainer(
      overrides: [developerModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    expect(container.read(developerModeProvider), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(developerModeProvider), isTrue);
    expect(store.reads, 1);
  });

  test('turning developer mode on/off persists the flag', () async {
    final store = MemoryDeveloperModeStore();
    final container = ProviderContainer(
      overrides: [developerModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container.read(developerModeProvider.notifier).setEnabled(true);
    expect(container.read(developerModeProvider), isTrue);
    expect(store.value, isTrue);
    expect(store.writes, 1);

    await container.read(developerModeProvider.notifier).setEnabled(false);
    expect(container.read(developerModeProvider), isFalse);
    expect(store.value, isFalse);
    expect(store.writes, 2);
  });

  test('a new container reads the previously persisted value', () async {
    final store = MemoryDeveloperModeStore();
    final first = ProviderContainer(
      overrides: [developerModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(first.dispose);
    await Future<void>.delayed(Duration.zero);
    await first.read(developerModeProvider.notifier).setEnabled(true);

    final second = ProviderContainer(
      overrides: [developerModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(second.dispose);
    expect(second.read(developerModeProvider), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(second.read(developerModeProvider), isTrue);
  });

  test('a user choice wins over a slow persisted read', () async {
    final store = MemoryDeveloperModeStore(true);
    final container = ProviderContainer(
      overrides: [developerModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    // Do not yield to the load future before the user turns it off.
    await container.read(developerModeProvider.notifier).setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(developerModeProvider), isFalse);
    expect(store.value, isFalse);
  });

  test(
    'the file store round-trips the flag and ignores damaged data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'zero-beat-mode-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = FileDeveloperModeStore(
        supportDirectory: () async => directory,
      );
      expect(await store.read(), isFalse);
      await store.write(true);
      expect(await store.read(), isTrue);
      await store.write(false);
      expect(await store.read(), isFalse);

      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${FileDeveloperModeStore.fileName}',
      );
      await file.writeAsString('not json');
      expect(await store.read(), isFalse);
    },
  );

  test('read and write failures leave the UI usable', () async {
    final readFailure = ProviderContainer(
      overrides: [
        developerModeStoreProvider.overrideWithValue(
          FailingDeveloperModeStore(failRead: true),
        ),
      ],
    );
    addTearDown(readFailure.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(readFailure.read(developerModeProvider), isFalse);

    final writeFailure = ProviderContainer(
      overrides: [
        developerModeStoreProvider.overrideWithValue(
          FailingDeveloperModeStore(failWrite: true),
        ),
      ],
    );
    addTearDown(writeFailure.dispose);
    await Future<void>.delayed(Duration.zero);
    await writeFailure.read(developerModeProvider.notifier).setEnabled(true);
    expect(writeFailure.read(developerModeProvider), isTrue);
  });
}
