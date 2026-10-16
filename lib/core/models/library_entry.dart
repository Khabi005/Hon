class LibraryEntry {
  final String bookId;
  final bool isInLibrary;
  final DateTime dateAdded;
  final DateTime? lastReadAt;
  final bool isFinished;
  final List<String> collectionIds;
  final int customSortOrder;

  const LibraryEntry({
    required this.bookId,
    required this.isInLibrary,
    required this.dateAdded,
    this.lastReadAt,
    this.isFinished = false,
    this.collectionIds = const [],
    this.customSortOrder = 0,
  });

  LibraryEntry copyWith({
    String? bookId,
    bool? isInLibrary,
    DateTime? dateAdded,
    DateTime? lastReadAt,
    bool? isFinished,
    List<String>? collectionIds,
    int? customSortOrder,
  }) {
    return LibraryEntry(
      bookId: bookId ?? this.bookId,
      isInLibrary: isInLibrary ?? this.isInLibrary,
      dateAdded: dateAdded ?? this.dateAdded,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      isFinished: isFinished ?? this.isFinished,
      collectionIds: collectionIds ?? this.collectionIds,
      customSortOrder: customSortOrder ?? this.customSortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookId': bookId,
      'isInLibrary': isInLibrary ? 1 : 0,
      'dateAdded': dateAdded.toIso8601String(),
      'lastReadAt': lastReadAt?.toIso8601String(),
      'isFinished': isFinished ? 1 : 0,
      'collectionIds': collectionIds.join(','),
      'customSortOrder': customSortOrder,
    };
  }

  factory LibraryEntry.fromMap(Map<String, dynamic> map) {
    return LibraryEntry(
      bookId: map['bookId'] as String,
      isInLibrary: (map['isInLibrary'] as int) == 1,
      dateAdded: DateTime.parse(map['dateAdded'] as String),
      lastReadAt: map['lastReadAt'] != null
          ? DateTime.parse(map['lastReadAt'] as String)
          : null,
      isFinished: (map['isFinished'] as int? ?? 0) == 1,
      collectionIds: (map['collectionIds'] as String? ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList(),
      customSortOrder: (map['customSortOrder'] as int?) ?? 0,
    );
  }
}
