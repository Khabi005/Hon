import '../database/database_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/novel_source.dart';
import '../models/reading_progress.dart';
import '../updates/chapter_update_service.dart';
import '../utils/html_utils.dart';

/// The outcome of moving a novel to another source.
class SourceMigrationResult {
  final Book book;

  /// The chapter on the new source the reader continues from, if the old
  /// one had a reading position.
  final Chapter? resumeChapter;

  const SourceMigrationResult(this.book, this.resumeChapter);
}

/// Moves a library web novel to the same novel on another source, as in
/// Shosetsu and LNReader: when a source dies, the reader keeps their place,
/// library spot, collections and finished flag. Highlights and bookmarks
/// stay with the old copy, since they point into the old source's text.
class SourceMigration {
  static final _numbered = RegExp(
    r'(?:chapter|ch\.?|episode|ep\.?|part)\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _anyNumber = RegExp(r'\d+(?:\.\d+)?');

  /// The chapter number in a title like "Chapter 12: …" or "Ch. 12", else
  /// the first number in it.
  static String? chapterNumber(String title) =>
      _numbered.firstMatch(title)?.group(1) ??
      _anyNumber.firstMatch(title)?.group(0);

  /// The chapter in [candidates] that best matches [old]: the same chapter
  /// number, then a similar title, then the same relative position.
  static int matchChapter(
    Chapter old,
    int oldIndex,
    int oldCount,
    List<Chapter> candidates,
  ) {
    if (candidates.isEmpty) return -1;
    final number = chapterNumber(old.title);
    if (number != null) {
      final match = candidates.indexWhere(
        (c) => chapterNumber(c.title) == number,
      );
      if (match >= 0) return match;
    }
    final similar = candidates.indexWhere(
      (c) => ChapterUpdateService.areTitlesSimilar(c.title, old.title),
    );
    if (similar >= 0) return similar;
    if (oldCount <= 1) return 0;
    final ratio = oldIndex / (oldCount - 1);
    return (ratio * (candidates.length - 1)).round().clamp(
      0,
      candidates.length - 1,
    );
  }

  static Future<SourceMigrationResult> migrate({
    required Book from,
    required String targetSourceId,
    required NovelDetails details,
  }) async {
    final db = DatabaseService.instance;
    final id = '$targetSourceId:${details.id}';
    if (id == from.id) {
      throw StateError('This is already the source of this novel.');
    }
    final now = DateTime.now();
    final existing = db.getBookById(id);
    final book = Book(
      id: id,
      title: details.title.isNotEmpty ? details.title : from.title,
      author: details.author.isNotEmpty ? details.author : from.author,
      description: details.description.isNotEmpty
          ? cleanHtmlSynopsis(details.description)
          : from.description,
      format: BookFormat.webNovel,
      sourceId: targetSourceId,
      sourceNovelId: details.id,
      totalChapters: details.chapters.length,
      coverPath: details.coverUrl ?? from.coverPath,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await db.saveBook(book);
    await db.ensureChaptersLoaded(id);
    final known = {
      for (final chapter in db.getChapters(id))
        chapter.sourceChapterId: chapter,
    };
    final chapters = [
      for (var i = 0; i < details.chapters.length; i++)
        known[details.chapters[i].id]?.copyWith(
              title: details.chapters[i].title,
              url: details.chapters[i].url ?? details.chapters[i].id,
              chapterIndex: i.toDouble(),
            ) ??
            Chapter(
              id: '$id:${details.chapters[i].id}',
              bookId: id,
              sourceChapterId: details.chapters[i].id,
              title: details.chapters[i].title,
              chapterIndex: i.toDouble(),
              url: details.chapters[i].url ?? details.chapters[i].id,
              updatedAt: now,
            ),
    ];
    await db.saveChapters(id, chapters);

    // Carry the reading position over by chapter.
    Chapter? resume;
    final progress = db.getProgress(from.id);
    await db.ensureChaptersLoaded(from.id);
    final oldChapters = db.getChapters(from.id);
    if (progress != null && oldChapters.isNotEmpty && chapters.isNotEmpty) {
      final oldIndex = progress.chapterIndex.floor().clamp(
        0,
        oldChapters.length - 1,
      );
      final match = matchChapter(
        oldChapters[oldIndex],
        oldIndex,
        oldChapters.length,
        chapters,
      );
      resume = chapters[match];
      await db.saveProgress(
        ReadingProgress(
          bookId: id,
          lastChapterId: resume.id,
          chapterIndex: match.toDouble(),
          completionPercentage: chapters.length > 1
              ? match / (chapters.length - 1)
              : 0,
          lastReadAt: progress.lastReadAt,
        ),
      );
    }

    // Take over the old copy's place in the library.
    final entry = db.getLibraryEntry(from.id);
    await db.setLibraryMembership(id, true);
    if (entry?.isFinished == true) await db.markBookFinished(id, true);
    final collections = entry?.collectionIds ?? const <String>[];
    if (collections.isNotEmpty) {
      await db.setBookCollections(id, collections);
    }
    await db.setLibraryMembership(from.id, false);
    return SourceMigrationResult(db.getBookById(id) ?? book, resume);
  }
}
