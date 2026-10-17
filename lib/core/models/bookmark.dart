class Bookmark {
  final String id;
  final String bookId;
  final int pageIndex; // For PDF: 1-indexed page. For EPUB: chapter index.
  final int? chapterIndex;
  final String label;
  final DateTime createdAt;
  final String? snippet;

  Bookmark({
    required this.id,
    required this.bookId,
    required this.pageIndex,
    this.chapterIndex,
    required this.label,
    required this.createdAt,
    this.snippet,
  });

  Bookmark copyWith({
    String? id,
    String? bookId,
    int? pageIndex,
    int? chapterIndex,
    String? label,
    DateTime? createdAt,
    String? snippet,
  }) {
    return Bookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      pageIndex: pageIndex ?? this.pageIndex,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
      snippet: snippet ?? this.snippet,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookId': bookId,
        'pageIndex': pageIndex,
        if (chapterIndex != null) 'chapterIndex': chapterIndex,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        if (snippet != null) 'snippet': snippet,
      };

  factory Bookmark.fromMap(Map<String, dynamic> map) => Bookmark(
        id: map['id'] as String,
        bookId: map['bookId'] as String,
        pageIndex: (map['pageIndex'] as num?)?.toInt() ?? 1,
        chapterIndex: (map['chapterIndex'] as num?)?.toInt(),
        label: map['label'] as String? ?? 'Bookmark',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        snippet: map['snippet'] as String?,
      );
}
