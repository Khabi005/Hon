import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_service.dart';
import '../core/native/readium_reader_service.dart';
import 'bootstrap/providers.dart';
import 'navigation/tab_scaffold.dart';
import 'theme/hon_theme.dart';
import 'theme/app_appearance.dart';
import 'theme/glass_surface.dart';

class HonApp extends ConsumerStatefulWidget {
  const HonApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  ConsumerState<HonApp> createState() => _HonAppState();
}

class _HonAppState extends ConsumerState<HonApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReadiumReaderService.onTypographyChanged = (bookId, typography) {
      ref
          .read(readerPreferencesProvider.notifier)
          .applyNativeTypography(typography, bookId: bookId);
    };
    ReadiumReaderService.onPreferencesChanged = (bookId, theme, scroll, fontSize) {
      ref
          .read(readerPreferencesProvider.notifier)
          .applyNative(theme: theme, scroll: scroll, fontSize: fontSize, bookId: bookId);
    };
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DatabaseService.instance.refreshAllChapters();
      DatabaseService.instance.refreshAllDownloads();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReadiumReaderService.onPreferencesChanged = null;
    ReadiumReaderService.onTypographyChanged = null;
    ReadiumReaderService.onErrorCallback = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rich = ref.watch(appAppearanceProvider) == AppAppearance.liquidGlass;
    ThemeData appearance(ThemeData base) => base.copyWith(
      extensions: [GlassStyle(rich: rich)],
      inputDecorationTheme: rich
          ? base.inputDecorationTheme.copyWith(
              fillColor: base.colorScheme.surface.withValues(alpha: .72),
            )
          : base.inputDecorationTheme,
      cardTheme: rich
          ? base.cardTheme.copyWith(
              color: base.colorScheme.surface.withValues(alpha: .78),
            )
          : base.cardTheme,
      scaffoldBackgroundColor: base.scaffoldBackgroundColor,
    );
    return MaterialApp(
      navigatorKey: HonApp.navigatorKey,
      title: 'Hon',
      debugShowCheckedModeBanner: false,
      theme: appearance(HonTheme.lightTheme),
      darkTheme: appearance(HonTheme.darkTheme),
      themeMode: ThemeMode.system,
      builder: (context, child) => rich
          ? GlassBackdrop(
              dark: Theme.of(context).brightness == Brightness.dark,
              child: child!,
            )
          : child!,
      home: const TabScaffold(),
    );
  }
}
