import '../features/navigation.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'library_page.dart';
import '../shared/player_bar.dart';
import '../shared/queue_panel.dart';
import 'discover_page.dart';
import 'full_player_page.dart';
import 'mine_page.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());

  void _openPlayer() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => FullPlayerPage()));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.zero.canvas,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: [
              for (var i = 0; i < 3; i++)
                NavigatorPopHandler<Object?>(
                  enabled: _tab == i,
                  onPopWithResult: (_) =>
                      _navigators[i].currentState?.maybePop(),
                  child: FeatureNavigation(
                    navigatorKey: _navigators[i],
                    child: Navigator(
                      key: _navigators[i],
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (context) => i == 0
                            ? const MobileLibraryPage()
                            : i == 1
                            ? const DiscoverPage()
                            : const MinePage(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1),
            PlayerBar(
              compact: true,
              onOpen: _openPlayer,
              onQueue: () => showQueueSheet(context),
            ),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  label: '曲库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  label: '发现',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: '我的',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
