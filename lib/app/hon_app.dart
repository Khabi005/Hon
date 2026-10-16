import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation/tab_scaffold.dart';
import 'theme/hon_theme.dart';

class HonApp extends ConsumerWidget {
  const HonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Hon',
      debugShowCheckedModeBanner: false,
      theme: HonTheme.lightTheme,
      darkTheme: HonTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const TabScaffold(),
    );
  }
}
