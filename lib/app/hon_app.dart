import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/native/readium_reader_service.dart';
import 'navigation/tab_scaffold.dart';
import 'theme/hon_theme.dart';

class HonApp extends ConsumerStatefulWidget {
  const HonApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  ConsumerState<HonApp> createState() => _HonAppState();
}

class _HonAppState extends ConsumerState<HonApp> {
  @override
  void initState() {
    super.initState();
    ReadiumReaderService.onErrorCallback = (bookId, code, message) {
      final ctx = HonApp.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2C2C2E),
            content: Text(
              'Reader error: $message ($code)',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: HonApp.navigatorKey,
      title: 'Hon',
      debugShowCheckedModeBanner: false,
      theme: HonTheme.lightTheme,
      darkTheme: HonTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const TabScaffold(),
    );
  }
}
