import 'playback.dart' show accountLabel;

/// The full Chinese name for a source. Cores may report a short display name
/// (for example "B站"), but the account screens always show the same complete
/// name for known sources so the mine page and the account list agree.
String accountDisplayName(String id, [String name = '']) {
  final known = accountLabel(id);
  if (known != id) return known;
  if (name.isNotEmpty) return name;
  return id;
}

/// Detailed login state used by the account list.
String accountLoginStatus({
  required bool loggedIn,
  required String name,
  required bool expired,
}) {
  if (loggedIn) return name.isEmpty ? '已登录' : '已登录 · $name';
  if (expired) return '登录已失效，请重新登录';
  return '未登录，仍可播放公开内容';
}

/// Short login state used by the mine page entry summaries.
String accountCompactStatus({required bool loggedIn, required bool expired}) {
  if (loggedIn) return '已登录';
  if (expired) return '登录已失效';
  return '未登录';
}
