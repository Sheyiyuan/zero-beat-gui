import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/shared/cover_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('netease covers request a small https image', () {
    expect(
      coverImageUrl('http://p2.music.126.net/abc==/1.jpg'),
      'https://p2.music.126.net/abc==/1.jpg?param=640y640',
    );
    expect(
      coverImageUrl('https://p2.music.126.net/abc==/1.jpg?param=640y640'),
      'https://p2.music.126.net/abc==/1.jpg?param=640y640',
    );
    expect(
      coverImageUrl('https://i0.hdslb.com/cover.jpg'),
      'https://i0.hdslb.com/cover.jpg',
    );
  });

  test('cover fetch does not send the Dart user agent', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _DirectHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final userAgent = Completer<String>();
    server.listen((request) {
      if (!userAgent.isCompleted) {
        userAgent.complete(
          request.headers.value(HttpHeaders.userAgentHeader) ?? '',
        );
      }
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
    });

    CoverImageProvider(
      'http://${server.address.address}:${server.port}/cover.jpg',
    ).resolve(ImageConfiguration.empty);

    final agent = await userAgent.future.timeout(const Duration(seconds: 5));
    expect(agent, isNot(contains('Dart')));
    expect(agent, contains('Mozilla'));
  });
}

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
  }
}
