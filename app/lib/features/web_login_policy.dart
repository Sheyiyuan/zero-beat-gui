/// Official same-device login. The page is the platform's own site; zero-beat
/// only accepts the session cookies that site sets after the user logs in.
const neteaseMobileLoginUrl = 'https://music.163.com/m/login';
const neteaseDesktopLoginUrl = 'https://music.163.com/';
const bilibiliLoginUrl = 'https://passport.bilibili.com/login';

const neteaseMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

const desktopWebUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const neteaseCookieNames = {
  'MUSIC_U',
  'MUSIC_A',
  '__csrf',
  'NMTID',
  '__remember_me',
  'os',
  'appver',
  'sDeviceId',
  'WNMCID',
  'WEVNSM',
};

const bilibiliCookieNames = {
  'SESSDATA',
  'bili_jct',
  'DedeUserID',
  'DedeUserID__ckMd5',
  'sid',
  'buvid3',
  'buvid4',
  'b_nut',
};

bool sameDeviceLoginFirst({required bool android}) => android;

String loginPageUrl(String source, {required bool phone}) {
  return switch (source) {
    'netease' => phone ? neteaseMobileLoginUrl : neteaseDesktopLoginUrl,
    'bilibili' => bilibiliLoginUrl,
    _ => '',
  };
}

String loginUserAgent(String source, {required bool phone}) {
  if (source == 'netease' && phone) return neteaseMobileUserAgent;
  return desktopWebUserAgent;
}

List<String> loginCookieUrls(String source) {
  return switch (source) {
    'netease' => const [
      'https://music.163.com',
      'https://y.music.163.com',
      'https://interface.music.163.com',
      'https://interface3.music.163.com',
    ],
    'bilibili' => const [
      'https://bilibili.com',
      'https://passport.bilibili.com',
      'https://www.bilibili.com',
      'https://m.bilibili.com',
    ],
    _ => const [],
  };
}

bool allowedLoginNavigation(String source, String url) {
  if (url == 'about:blank') return true;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  bool domain(String root) => host == root || host.endsWith('.$root');
  return switch (source) {
    'netease' => domain('163.com') || domain('126.net') || domain('126.com'),
    'bilibili' => domain('bilibili.com'),
    _ => false,
  };
}

/// Drops anything the core will not store. Required cookie must be present.
Map<String, String> sessionCookies(String source, Map<String, String> raw) {
  final allowed = switch (source) {
    'netease' => neteaseCookieNames,
    'bilibili' => bilibiliCookieNames,
    _ => const <String>{},
  };
  final required = switch (source) {
    'netease' => 'MUSIC_U',
    'bilibili' => 'SESSDATA',
    _ => '',
  };
  if (allowed.isEmpty || required.isEmpty) return const {};
  final out = <String, String>{};
  for (final entry in raw.entries) {
    final name = entry.key.trim();
    final value = entry.value.trim();
    if (!allowed.contains(name) || value.isEmpty) continue;
    if (name.contains('\n') || value.contains('\n') || value.contains(';')) {
      continue;
    }
    out[name] = value;
  }
  if ((out[required] ?? '').isEmpty) return const {};
  return out;
}
