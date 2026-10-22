class ChapterDeletionResult {
  final int requestedCount;
  final int deletedCount;
  final int failedCount;
  final int skippedCount;
  final List<String> failedChapterIds;
  final List<String> errors;

  const ChapterDeletionResult({
    required this.requestedCount,
    required this.deletedCount,
    required this.failedCount,
    required this.skippedCount,
    this.failedChapterIds = const [],
    this.errors = const [],
  });

  bool get isFullSuccess => failedCount == 0;
  bool get hasFailures => failedCount > 0;

  @override
  bool operator ==(Object other) {
    if (other is int) return deletedCount == other;
    if (other is ChapterDeletionResult) {
      return deletedCount == other.deletedCount &&
          failedCount == other.failedCount &&
          skippedCount == other.skippedCount;
    }
    return false;
  }

  @override
  int get hashCode => deletedCount.hashCode ^ failedCount.hashCode;

  @override
  String toString() =>
      'ChapterDeletionResult(deleted: $deletedCount, failed: $failedCount, skipped: $skippedCount)';
}
