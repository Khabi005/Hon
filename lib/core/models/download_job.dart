enum DownloadStatus {
  queued,
  running,
  completed,
  retryWaiting,
  paused,
  cancelled,
  failed,
}

class DownloadJob {
  final String id;
  final String bookId;
  final String chapterId;
  final String chapterTitle;
  final String sourceId;
  final DownloadStatus status;
  final double progress; // 0.0 - 1.0
  final int retryCount;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DownloadJob({
    required this.id,
    required this.bookId,
    required this.chapterId,
    required this.chapterTitle,
    required this.sourceId,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.retryCount = 0,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.running ||
      status == DownloadStatus.retryWaiting;

  DownloadJob copyWith({
    String? id,
    String? bookId,
    String? chapterId,
    String? chapterTitle,
    String? sourceId,
    DownloadStatus? status,
    double? progress,
    int? retryCount,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DownloadJob(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterId: chapterId ?? this.chapterId,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      sourceId: sourceId ?? this.sourceId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'sourceId': sourceId,
      'status': status.name,
      'progress': progress,
      'retryCount': retryCount,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DownloadJob.fromMap(Map<String, dynamic> map) {
    return DownloadJob(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      chapterId: map['chapterId'] as String,
      chapterTitle: map['chapterTitle'] as String,
      sourceId: map['sourceId'] as String,
      status: DownloadStatus.values.byName(map['status'] as String),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      retryCount: (map['retryCount'] as int?) ?? 0,
      errorMessage: map['errorMessage'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
