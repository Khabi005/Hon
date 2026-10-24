import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/theme/reader_theme.dart';
import 'package:hon/features/reader/epub_menus/epub_menu_app.dart';
import 'package:hon/features/reader/epub_menus/epub_menu_state.dart';

class _FakeHost implements EpubMenuHost {
  final calls = <(String, Map<String, Object?>?)>[];
  Object? Function(String method, Map<String, Object?>? arguments)? answer;

  Iterable<String> get methods => calls.map((call) => call.$1);

  @override
  Future<Object?> call(String method, [Map<String, Object?>? arguments]) async {
    calls.add((method, arguments));
    return answer?.call(method, arguments);
  }
}

final _state = EpubMenuState.fromMap({
  'title': 'A Fixed Star',
  'chapterIndex': 1,
  'chapterCount': 3,
  'currentToc': 1,
  'toc': [
    {'title': 'Opening', 'depth': 0},
    {'title': 'The Middle', 'depth': 0},
    {'title': 'A Part', 'depth': 1},
  ],
  'bookmarks': [
    {'label': 'Saved spot', 'chapterIndex': 1},
  ],
  'highlights': [
    {'id': 'h1', 'text': 'A line worth keeping', 'color': 'blue'},
  ],
  'canReflow': true,
  'preferences': {'theme': 'calm', 'layout': 'paginated', 'size': 18.0},
});

void main() {
  late _FakeHost host;
  late EpubMenuController controller;

  Future<void> pumpApp(WidgetTester tester) async {
    host = _FakeHost();
    controller = EpubMenuController();
    await tester.pumpWidget(
      EpubMenuApp(
        host: host,
        controller: controller,
        closeDelay: const Duration(milliseconds: 50),
      ),
    );
  }

  test('reads the state the native reader sends', () {
    expect(_state.toc, hasLength(3));
    expect(_state.toc[2].depth, 1);
    expect(_state.isBookmarked, isTrue);
    expect(_state.highlights.single.color, 'blue');
    expect(_state.preferences.themePreset, ReaderThemePreset.calm);
    expect(EpubMenuState.fromMap({}).currentToc, -1);
  });

  testWidgets('contents go to the chosen entry, then close', (tester) async {
    await pumpApp(tester);
    controller.show(EpubMenuSheet.contents, _state);
    await tester.pumpAndSettle();
    expect(find.text('A Fixed Star'), findsOneWidget);
    expect(find.text('Chapter 2 of 3'), findsOneWidget);
    await tester.tap(find.text('A Part'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.calls.first.$1, 'goToToc');
    expect(host.calls.first.$2, {'index': 2});
    expect(host.methods.last, 'closed');
  });

  testWidgets('highlights can be deleted from contents', (tester) async {
    await pumpApp(tester);
    host.answer = (method, _) =>
        method == 'deleteHighlight' ? <Object>[] : null;
    controller.show(EpubMenuSheet.contents, _state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlights'));
    await tester.pumpAndSettle();
    expect(find.text('A line worth keeping'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete highlight'));
    await tester.pumpAndSettle();
    expect(find.text('No Highlights'), findsOneWidget);
    expect(host.methods, contains('deleteHighlight'));
  });

  testWidgets('the menu opens other sheets without closing', (tester) async {
    await pumpApp(tester);
    controller.show(EpubMenuSheet.menu, _state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contents'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The Middle'), findsOneWidget);
    expect(host.methods, isNot(contains('closed')));

    controller.back();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The Middle'), findsNothing);
    expect(host.methods.last, 'closed');
  });

  testWidgets('theme changes go to the native reader', (tester) async {
    await pumpApp(tester);
    controller.show(EpubMenuSheet.appearance, _state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiet'));
    await tester.pumpAndSettle();
    final change = host.calls.lastWhere((call) => call.$1 == 'setPreferences');
    expect(change.$2!['theme'], 'quiet');
    expect(change.$2!['size'], 18.0);

    host.answer = (method, _) => method == 'resetPreferences'
        ? {'theme': 'paper', 'layout': 'paginated', 'size': 20.0}
        : null;
    await tester.tap(find.text('Reset to Defaults'));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('search shows matches and goes to one', (tester) async {
    await pumpApp(tester);
    host.answer = (method, arguments) => method == 'search'
        ? [
            {
              'title': 'The Middle',
              'before': 'where the ',
              'highlight': arguments!['query'],
              'after': ' waits',
            },
          ]
        : null;
    controller.show(EpubMenuSheet.search, _state);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'river');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('1 match'), findsOneWidget);
    await tester.tap(find.textContaining('where the river', findRichText: true));
    await tester.pumpAndSettle();
    final go = host.calls.lastWhere((call) => call.$1 == 'goToSearchResult');
    expect(go.$2, {'index': 0});
  });
}
