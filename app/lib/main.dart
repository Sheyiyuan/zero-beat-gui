import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/developer_log.dart';
import 'core/startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape is not laid out yet; a rotation turns the phone into a wide
  // screen and breaks the player. Keep the activity portrait.
  if (Platform.isAndroid) {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }
  installDeveloperLogErrorHandlers();
  runApp(const CoreStartup());
}
