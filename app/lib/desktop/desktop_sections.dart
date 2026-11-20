import 'package:flutter/widgets.dart';

import '../app/icons.dart';

/// Top-level desktop destinations. Each one replaces the main column; feature
/// pages opened from it stack on top until another destination is chosen.
enum DesktopSection {
  library('曲库', AppIcons.library),
  discover('发现', AppIcons.discover),
  downloads('下载', AppIcons.download),
  sync('同步', AppIcons.sync),
  accounts('账号', AppIcons.account),
  settings('设置', AppIcons.settings);

  const DesktopSection(this.label, this.icon);

  final String label;
  final IconData icon;

  static const primary = [library, discover, downloads, sync];
}

typedef SectionCallback = void Function(DesktopSection section);
