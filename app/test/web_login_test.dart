import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/app/theme.dart';
import 'package:zero_beat_gui/features/accounts_page.dart';
import 'package:zero_beat_gui/features/web_login_page.dart';
import 'package:zero_beat_gui/features/web_login_policy.dart';

import 'full_feature_test.dart';

void main() {
  test('same-device login only keeps the official session cookies', () {
    expect(
      allowedLoginNavigation('netease', 'https://music.163.com/m/login'),
      isTrue,
    );
    expect(
      allowedLoginNavigation('netease', 'http://music.163.com/m/login'),
      isFalse,
    );
    expect(
      allowedLoginNavigation('netease', 'https://evil.example/music.163.com'),
      isFalse,
    );
    expect(
      allowedLoginNavigation('bilibili', 'https://passport.bilibili.com/login'),
      isTrue,
    );
    expect(
      allowedLoginNavigation('bilibili', 'https://music.163.com/m/login'),
      isFalse,
    );
    const secret = 'music-u-secret';
    final kept = sessionCookies('netease', {
      'MUSIC_U': secret,
      'password': 'should-not-pass',
      '__csrf': 'csrf',
    });
    expect(kept.keys, containsAll(['MUSIC_U', '__csrf']));
    expect(kept.containsKey('password'), isFalse);
    expect(sessionCookies('bilibili', {'MUSIC_U': secret}), isEmpty);
    expect(loginPageUrl('netease', phone: true), neteaseMobileLoginUrl);
    expect(loginPageUrl('bilibili', phone: true), bilibiliLoginUrl);
  });

  testWidgets('android login offers the official page before a qr code', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpOptions(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('login-on-device'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('login-qr'))).dy),
      );
      expect(find.text('在本机登录'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop login keeps the qr code as the primary action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _pumpOptions(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('login-qr'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('login-on-device'))).dy,
        ),
      );
      final filled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '二维码'),
      );
      expect(filled.onPressed, isNotNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'completed official login is submitted without showing the cookie',
    (tester) async {
      const secret = 'music-u-secret';
      final api = FeatureApi();
      addTearDown(api.closeControllers);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpOptions(
          tester,
          api: api,
          cookies: (_) async => {'MUSIC_U': secret, 'password': 'hidden'},
          viewport: const Text('official-login'),
        );
        await tester.tap(find.text('在本机登录'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('official-login'), findsOneWidget);
        expect(find.textContaining(secret), findsNothing);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining(secret), findsNothing);
        final commit = api.calls.where((call) => call.$1 == 'auth.web.commit');
        expect(commit, isNotEmpty);
        final sent = Map<String, Object?>.from(
          commit.first.$2['cookies'] as Map,
        );
        expect(sent['MUSIC_U'], secret);
        expect(sent.containsKey('password'), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

Future<void> _pumpOptions(
  WidgetTester tester, {
  FeatureApi? api,
  WebCookieReader? cookies,
  Widget? viewport,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [coreApiProvider.overrideWithValue(api ?? FeatureApi())],
      child: MaterialApp(
        theme: buildZeroTheme(),
        home: Scaffold(
          body: LoginOptions(
            source: 'netease',
            title: '网易云',
            cookies: cookies,
            viewport: viewport,
          ),
        ),
      ),
    ),
  );
}
