import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/novel_source.dart';
import 'package:hon/core/sources/source_preferences.dart';
import 'package:hon/features/browse/presentation/chapter_download_sheet.dart';
import 'package:hon/features/settings/presentation/source_controls_screen.dart';

void main() {
  testWidgets(
    'Chapter picker validates range and queues selected unread chapters',
    (tester) async {
      Set<String>? selected;
      final chapters = List.generate(
        5,
        (index) => Chapter(
          id: '$index',
          bookId: 'book',
          sourceChapterId: '$index',
          title: 'Chapter ${index + 1}',
          chapterIndex: index.toDouble(),
          downloadState: index == 2
              ? ChapterDownloadState.downloaded
              : ChapterDownloadState.notDownloaded,
          updatedAt: DateTime(2026, 10, 19),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<Set<String>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ChapterDownloadSheet(
                      chapters: chapters,
                      unreadStart: 2,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('Select'));
      await tester.pump();
      expect(find.text('Enter a valid chapter range.'), findsOneWidget);
      await tester.tap(find.text('All Missing'));
      await tester.pump();
      expect(find.text('4 selected'), findsOneWidget);
      await tester.tap(find.text('Unread'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      expect(selected, {'3', '4'});
    },
  );

  testWidgets(
    'Source controls reset editor values and save typed preferences and filters',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SourcePreferences.save('gutenberg', {'1': false});
      await SourcePreferences.save('gutenberg', {
        '2': 'old author',
      }, filters: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SourceControlsScreen(
                      sourceId: 'gutenberg',
                      name: 'Test Source',
                      info: SourceCatalogInfo(
                        settings: [
                          SourceControl(
                            id: 1,
                            label: 'Publisher formatting',
                            group: '',
                            kind: 'SwitchFilter',
                            value: true,
                          ),
                        ],
                        filters: [
                          SourceControl(
                            id: 2,
                            label: 'Author',
                            group: '',
                            kind: 'TextFilter',
                            value: '',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        'old author',
      );
      await tester.scrollUntilVisible(
        find.text('Reset to Source Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset to Source Defaults'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(SwitchListTile),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await tester.scrollUntilVisible(
        find.byType(TextFormField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        '',
      );
      await tester.enterText(find.byType(TextFormField), 'new author');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await SourcePreferences.read('gutenberg'), isEmpty);
      expect(await SourcePreferences.read('gutenberg', filters: true), {
        '2': 'new author',
      });
    },
  );
}
