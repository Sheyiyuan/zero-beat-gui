import 'package:flutter/widgets.dart';

import 'core/startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CoreStartup());
}
