import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:night_watch_flutter/services/background_service.dart';
import 'package:night_watch_flutter/services/monitoring_controller.dart';
import 'package:night_watch_flutter/ui/screens/monitor_screen.dart';
import 'package:night_watch_flutter/ui/screens/sessions_screen.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive dark status & navigation bars
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: NightWatchTheme.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await BackgroundServiceManager.init();
  await MonitoringController().init();

  runApp(const NightWatchApp());
}

class NightWatchApp extends StatelessWidget {
  const NightWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Night Watch',
      debugShowCheckedModeBanner: false,
      theme: NightWatchTheme.darkTheme,
      home: const MainNavigationHolder(),
    );
  }
}

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    MonitorScreen(),
    SessionsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nightlight_outlined),
            selectedIcon: Icon(Icons.nightlight_rounded),
            label: 'Night Watch',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_toggle_off_rounded),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
