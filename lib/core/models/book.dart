enum BookFormat {
  epub,
  pdf,
  webNovel,
}

class Book {
  final String id;
  final String title;
  final String author;
  final String description;
  final String? coverPath;
  final BookFormat format;
  final String? sourceId; // Source identity if online novel
  final String? sourceNovelId; // Source-native identifier
  final String? filePath; // App-private file path for EPUB/PDF
  final String? contentHash; // SHA-256 for duplicate detection
  final int totalChapters;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Book({
    required this.id,
    required this.title,
    this.author = 'Unknown Author',
    this.description = '',
    this.coverPath,
    required this.format,
    this.sourceId,
    this.sourceNovelId,
    this.filePath,
    this.contentHash,
    this.totalChapters = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? description,
    String? coverPath,
    BookFormat? format,
    String? sourceId,
    String? sourceNovelId,
    String? filePath,
    String? contentHash,
    int? totalChapters,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      coverPath: coverPath ?? this.coverPath,
      format: format ?? this.format,
      sourceId: sourceId ?? this.sourceId,
      sourceNovelId: sourceNovelId ?? this.sourceNovelId,
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      totalChapters: totalChapters ?? this.totalChapters,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'coverPath': coverPath,
      'format': format.name,
      'sourceId': sourceId,
      'sourceNovelId': sourceNovelId,
      'filePath': filePath,
      'contentHash': contentHash,
      'totalChapters': totalChapters,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as String,
      title: map['title'] as String,
      author: (map['author'] as String?) ?? 'Unknown Author',
      description: (map['description'] as String?) ?? '',
      coverPath: map['coverPath'] as String?,
      format: BookFormat.values.byName(map['format'] as String),
      sourceId: map['sourceId'] as String?,
      sourceNovelId: map['sourceNovelId'] as String?,
      filePath: map['filePath'] as String?,
      contentHash: map['contentHash'] as String?,
      totalChapters: (map['totalChapters'] as int?) ?? 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
