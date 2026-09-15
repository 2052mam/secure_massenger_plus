import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/presence_service.dart';
import 'chat_list_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/music/mini_music_player.dart';

final shellIndexProvider = StateProvider.autoDispose<int>((ref) {
  ref.watch(authNotifierProvider.select((auth) => auth.valueOrNull?.id));
  return 0;
});

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late PresenceService _presence;
  late final String? _sessionUserId;
  String? _presenceToken;

  @override
  void initState() {
    super.initState();
    final session = ref.read(authenticatedSessionProvider);
    _sessionUserId = session.userId;
    _presenceToken = session.token;
    _presence = PresenceService(session.api)..start();
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authenticatedSessionProvider, (_, session) {
      if (session.userId == _sessionUserId && session.token != _presenceToken) {
        _presence.dispose(reportOffline: false);
        _presenceToken = session.token;
        _presence = PresenceService(session.api)..start();
      }
    });
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final index = ref.watch(shellIndexProvider);

    final pages = [
      const ChatListScreen(),
      const SearchScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniMusicPlayer(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) =>
                ref.read(shellIndexProvider.notifier).state = i,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.chat_bubble_outline),
                selectedIcon: const Icon(Icons.chat_bubble),
                label: isFa ? 'چت‌ها' : 'Chats',
              ),
              NavigationDestination(
                icon: const Icon(Icons.search),
                selectedIcon: const Icon(Icons.search),
                label: isFa ? 'جستجو' : 'Search',
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: isFa ? 'تنظیمات' : 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
