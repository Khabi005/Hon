import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/app/theme/app_appearance.dart';
import 'package:hon/app/theme/glass_surface.dart';
import 'package:hon/app/theme/hon_theme.dart';
import 'package:hon/features/settings/presentation/app_appearance_section.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Appearance persists, restores, and saves rapid choices in order',
    () async {
      final first = AppAppearanceNotifier();
      await first.ready;
      expect(first.state, AppAppearance.standard);
      await Future.wait([
        first.select(AppAppearance.liquidGlass),
        first.select(AppAppearance.standard),
        first.select(AppAppearance.liquidGlass),
      ]);
      first.dispose();
      final restored = AppAppearanceNotifier();
      await restored.ready;
      expect(restored.state, AppAppearance.liquidGlass);
      restored.dispose();
    },
  );

  testWidgets('Appearance selection works at large text and narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appAppearanceProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HonTheme.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(child: AppAppearanceSection()),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Liquid Glass'));
    await tester.pumpAndSettle();
    expect(container.read(appAppearanceProvider), AppAppearance.liquidGlass);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Glass is bounded and high contrast removes blur', (
    tester,
  ) async {
    Future<void> render(bool rich, bool contrast) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HonTheme.darkTheme.copyWith(
            extensions: [GlassStyle(rich: rich)],
          ),
          home: MediaQuery(
            data: MediaQueryData(highContrast: contrast),
            child: const Scaffold(
              body: Column(
                children: [
                  GlassSurface(navigation: true, child: Text('Tabs')),
                  GlassSurface(child: Text('Card')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render(false, false);
    expect(find.byType(BackdropFilter), findsOneWidget);
    await render(true, false);
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    await render(true, true);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
