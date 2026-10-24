import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/shared/widgets/book_open_route.dart';

class _Page extends StatefulWidget {
  const _Page();

  static int created = 0;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _Page.created++;
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.expand(key: ValueKey('page')));
}

void main() {
  Future<Route<void>> open(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    final cover = CoverOrigin();
    late Route<void> route;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: reduceMotion,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 40, top: 100),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      route = BookOpenRoute.to<void>(
                        context,
                        origin: cover.rect,
                        builder: (_) => const _Page(),
                      );
                      Navigator.of(context).push(route);
                    },
                    child: cover.wrap(
                      const SizedBox(
                        key: ValueKey('cover'),
                        width: 80,
                        height: 120,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('cover')));
    await tester.pump();
    return route;
  }

  testWidgets('opening grows out of the cover and keeps the page state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _Page.created = 0;
    final route = await open(tester);
    expect(route, isA<BookOpenRoute<void>>());

    await tester.pump(const Duration(milliseconds: 1));
    final start = tester.getRect(find.byType(ClipRRect).last);
    expect(start.left, closeTo(40, 2));
    expect(start.top, closeTo(100, 2));
    expect(start.width, closeTo(80, 4));

    await tester.pump(const Duration(milliseconds: 200));
    final middle = tester.getRect(find.byType(ClipRRect).last);
    expect(middle.width, greaterThan(80));
    expect(middle.width, lessThan(400));

    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('page'))),
      const Rect.fromLTWH(0, 0, 400, 800),
    );
    expect(
      _Page.created,
      1,
      reason: 'the page must not be rebuilt from scratch',
    );
  });

  testWidgets('reduce motion opens the usual modal', (tester) async {
    final route = await open(tester, reduceMotion: true);
    expect(route, isA<MaterialPageRoute<void>>());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page')), findsOneWidget);
  });
}
