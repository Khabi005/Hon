class ReadingProgress {
  final String bookId;
  final String? lastChapterId;
  final double chapterIndex;
  final int pageIndex; // For PDF or Paginated EPUB
  final int totalPages;
  final double scrollOffset; // For continuous scroll
  final String? locatorString; // EPUB CFI or semantic DOM anchor
  final double completionPercentage; // 0.0 - 1.0
  final DateTime lastReadAt;

  const ReadingProgress({
    required this.bookId,
    this.lastChapterId,
    this.chapterIndex = 0.0,
    this.pageIndex = 0,
    this.totalPages = 1,
    this.scrollOffset = 0.0,
    this.locatorString,
    this.completionPercentage = 0.0,
    required this.lastReadAt,
  });

  String get formattedProgress {
    final pct = (completionPercentage * 100).toInt();
    if (totalPages > 1) {
      return '$pct% • Page ${pageIndex + 1} of $totalPages';
    }
    return '$pct%';
  }

  ReadingProgress copyWith({
    String? bookId,
    String? lastChapterId,
    double? chapterIndex,
    int? pageIndex,
    int? totalPages,
    double? scrollOffset,
    String? locatorString,
    double? completionPercentage,
    DateTime? lastReadAt,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      lastChapterId: lastChapterId ?? this.lastChapterId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      pageIndex: pageIndex ?? this.pageIndex,
      totalPages: totalPages ?? this.totalPages,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      locatorString: locatorString ?? this.locatorString,
      completionPercentage: completionPercentage ?? this.completionPercentage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookId': bookId,
      'lastChapterId': lastChapterId,
      'chapterIndex': chapterIndex,
      'pageIndex': pageIndex,
      'totalPages': totalPages,
      'scrollOffset': scrollOffset,
      'locatorString': locatorString,
      'completionPercentage': completionPercentage,
      'lastReadAt': lastReadAt.toIso8601String(),
    };
  }

  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    return ReadingProgress(
      bookId: map['bookId'] as String,
      lastChapterId: map['lastChapterId'] as String?,
      chapterIndex: (map['chapterIndex'] as num?)?.toDouble() ?? 0.0,
      pageIndex: (map['pageIndex'] as int?) ?? 0,
      totalPages: (map['totalPages'] as int?) ?? 1,
      scrollOffset: (map['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      locatorString: map['locatorString'] as String?,
      completionPercentage: (map['completionPercentage'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: DateTime.parse(map['lastReadAt'] as String),
    );
  }
}
