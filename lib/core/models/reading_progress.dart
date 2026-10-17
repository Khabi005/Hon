class ReadingProgress {
  final String bookId;
  final String? lastChapterId;
  final double chapterIndex;
  final int pageIndex; // For PDF or Paginated EPUB
  final int totalPages;
  final double scrollOffset; // For continuous scroll
  final String? locatorString; // EPUB CFI, Readium JSON, or semantic DOM anchor
  final String? locatorVersion; // 'readium-v1' or 'dart-dom-v1'
  final double completionPercentage; // 0.0 - 1.0 (whole-book progress)
  final DateTime lastReadAt;

  const ReadingProgress({
    required this.bookId,
    this.lastChapterId,
    this.chapterIndex = 0.0,
    this.pageIndex = 0,
    this.totalPages = 1,
    this.scrollOffset = 0.0,
    this.locatorString,
    this.locatorVersion,
    this.completionPercentage = 0.0,
    required this.lastReadAt,
  });

  /// True if the locator is serialized in Readium JSON format
  bool get isReadiumLocator =>
      locatorVersion == 'readium-v1' ||
      (locatorString != null && locatorString!.trim().startsWith('{'));

  /// True if the locator is serialized in Dart DOM offset format
  bool get isDartLocator =>
      locatorVersion == 'dart-dom-v1' ||
      (locatorString != null && locatorString!.contains('#offset='));

  String get formattedProgress {
    final pct = (completionPercentage * 100).toInt();
    if (totalPages > 1) {
      final displayPage = (pageIndex > 0 && pageIndex <= totalPages)
          ? pageIndex
          : (pageIndex + 1).clamp(1, totalPages);
      return '$pct% • Page $displayPage of $totalPages';
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
    String? locatorVersion,
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
      locatorVersion: locatorVersion ?? this.locatorVersion,
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
      'locatorVersion': locatorVersion ?? (isReadiumLocator ? 'readium-v1' : isDartLocator ? 'dart-dom-v1' : null),
      'completionPercentage': completionPercentage,
      'lastReadAt': lastReadAt.toIso8601String(),
    };
  }

  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    final locStr = map['locatorString'] as String?;
    final explicitVersion = map['locatorVersion'] as String?;
    final derivedVersion = explicitVersion ?? (locStr != null && locStr.trim().startsWith('{')
        ? 'readium-v1'
        : locStr != null && locStr.contains('#offset=')
            ? 'dart-dom-v1'
            : null);

    return ReadingProgress(
      bookId: map['bookId'] as String,
      lastChapterId: map['lastChapterId'] as String?,
      chapterIndex: (map['chapterIndex'] as num?)?.toDouble() ?? 0.0,
      pageIndex: (map['pageIndex'] as int?) ?? 0,
      totalPages: (map['totalPages'] as int?) ?? 1,
      scrollOffset: (map['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      locatorString: locStr,
      locatorVersion: derivedVersion,
      completionPercentage: (map['completionPercentage'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: DateTime.parse(map['lastReadAt'] as String),
    );
  }
}
