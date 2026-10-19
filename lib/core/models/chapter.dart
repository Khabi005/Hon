enum ChapterDownloadState {
  notDownloaded,
  queued,
  downloading,
  downloaded,
  failed,
  paused,
}

class Chapter {
  final String id;
  final String bookId;
  final String sourceChapterId;
  final String title;
  final double chapterIndex;
  final String? url;
  final String? localFilePath;
  final ChapterDownloadState downloadState;
  final DateTime? releaseDate;
  final DateTime updatedAt;

  const Chapter({
    required this.id,
    required this.bookId,
    required this.sourceChapterId,
    required this.title,
    required this.chapterIndex,
    this.url,
    this.localFilePath,
    this.downloadState = ChapterDownloadState.notDownloaded,
    this.releaseDate,
    required this.updatedAt,
  });

  Chapter copyWith({
    String? id,
    String? bookId,
    String? sourceChapterId,
    String? title,
    double? chapterIndex,
    String? url,
    String? localFilePath,
    ChapterDownloadState? downloadState,
    DateTime? releaseDate,
    DateTime? updatedAt,
  }) {
    return Chapter(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      sourceChapterId: sourceChapterId ?? this.sourceChapterId,
      title: title ?? this.title,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      url: url ?? this.url,
      localFilePath: localFilePath ?? this.localFilePath,
      downloadState: downloadState ?? this.downloadState,
      releaseDate: releaseDate ?? this.releaseDate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'sourceChapterId': sourceChapterId,
      'title': title,
      'chapterIndex': chapterIndex,
      'url': url,
      'localFilePath': localFilePath,
      'downloadState': downloadState.name,
      'releaseDate': releaseDate?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      sourceChapterId: map['sourceChapterId'] as String,
      title: map['title'] as String,
      chapterIndex: (map['chapterIndex'] as num).toDouble(),
      url: map['url'] as String?,
      localFilePath: map['localFilePath'] as String?,
      downloadState: ChapterDownloadState.values.firstWhere(
        (s) => s.name == map['downloadState'],
        orElse: () => ChapterDownloadState.notDownloaded,
      ),
      releaseDate: map['releaseDate'] != null
          ? DateTime.parse(map['releaseDate'] as String)
          : null,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
