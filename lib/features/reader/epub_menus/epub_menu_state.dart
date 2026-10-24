import '../../../app/theme/reader_theme.dart';

/// One line of an EPUB's table of contents.
class EpubTocEntry {
  final String title;
  final int depth;
  const EpubTocEntry(this.title, this.depth);
}

class EpubBookmarkEntry {
  final String label;
  final int? chapterIndex;
  final String? snippet;
  const EpubBookmarkEntry(this.label, {this.chapterIndex, this.snippet});
}

class EpubHighlightEntry {
  final String id;
  final String text;
  final String? note;
  final String color;
  const EpubHighlightEntry(
    this.id,
    this.text, {
    this.note,
    this.color = 'yellow',
  });
}

/// What the native EPUB reader sends when it opens a menu. Lists are
/// addressed by index when the menu asks the reader to go somewhere.
class EpubMenuState {
  final String title;
  final int chapterIndex;
  final int chapterCount;

  /// The table of contents entry being read, or -1.
  final int currentToc;
  final List<EpubTocEntry> toc;
  final List<EpubBookmarkEntry> bookmarks;
  final List<EpubHighlightEntry> highlights;

  /// False for fixed-layout books: no font or scroll settings.
  final bool canReflow;
  final bool isGlass;
  final bool rotationLocked;
  final ReaderPreferencesState preferences;

  const EpubMenuState({
    this.title = '',
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.currentToc = -1,
    this.toc = const [],
    this.bookmarks = const [],
    this.highlights = const [],
    this.canReflow = true,
    this.isGlass = false,
    this.rotationLocked = false,
    this.preferences = const ReaderPreferencesState(),
  });

  bool get isBookmarked =>
      bookmarks.any((bookmark) => bookmark.chapterIndex == chapterIndex);

  EpubMenuState copyWith({
    List<EpubHighlightEntry>? highlights,
    ReaderPreferencesState? preferences,
  }) => EpubMenuState(
    title: title,
    chapterIndex: chapterIndex,
    chapterCount: chapterCount,
    currentToc: currentToc,
    toc: toc,
    bookmarks: bookmarks,
    highlights: highlights ?? this.highlights,
    canReflow: canReflow,
    isGlass: isGlass,
    rotationLocked: rotationLocked,
    preferences: preferences ?? this.preferences,
  );

  factory EpubMenuState.fromMap(Map<dynamic, dynamic> map) {
    List<Map<dynamic, dynamic>> list(String key) => [
      for (final item in map[key] as List? ?? const [])
        if (item is Map) item,
    ];
    int number(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    final preferences = map['preferences'];
    return EpubMenuState(
      title: map['title'] as String? ?? '',
      chapterIndex: number(map['chapterIndex'], 0),
      chapterCount: number(map['chapterCount'], 0),
      currentToc: number(map['currentToc'], -1),
      toc: [
        for (final item in list('toc'))
          EpubTocEntry(
            item['title'] as String? ?? 'Chapter',
            number(item['depth'], 0),
          ),
      ],
      bookmarks: [
        for (final item in list('bookmarks'))
          EpubBookmarkEntry(
            item['label'] as String? ?? 'Bookmark',
            chapterIndex: item['chapterIndex'] is num
                ? (item['chapterIndex'] as num).toInt()
                : null,
            snippet: item['snippet'] as String?,
          ),
      ],
      highlights: highlightsFrom(map['highlights']),
      canReflow: map['canReflow'] as bool? ?? true,
      isGlass: map['isGlass'] as bool? ?? false,
      rotationLocked: map['rotationLocked'] as bool? ?? false,
      preferences: preferences is Map
          ? ReaderPreferencesState.fromMap(
              Map<String, dynamic>.from(preferences),
            )
          : const ReaderPreferencesState(),
    );
  }

  static List<EpubHighlightEntry> highlightsFrom(Object? raw) => [
    for (final item in raw as List? ?? const [])
      if (item is Map && item['id'] is String)
        EpubHighlightEntry(
          item['id'] as String,
          item['text'] as String? ?? '',
          note: item['note'] as String?,
          color: item['color'] as String? ?? 'yellow',
        ),
  ];
}
