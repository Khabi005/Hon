import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/app_database.dart';
import '../database/database_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/novel_source.dart';
import '../sources/source_registry.dart';
import '../utils/log_ignored.dart';

class ChapterUpdateService extends ChangeNotifier {
  static final instance = ChapterUpdateService();
  final Future<NovelDetails> Function(String source, String novel)? fetch;
  ChapterUpdateService({this.fetch});

  bool checking = false;
  final Map<String, String> errors = {};
  List<Map<String, dynamic>> history = [];
  final Map<String, List<Chapter>> unresolvedChaptersByBook = {};
  DateTime? lastCheck;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseService.instance.db;

    // Migrate from SharedPreferences if Drift table is empty
    final countExp = db.chapterUpdateHistoryTable.id.count();
    final countQuery = db.selectOnly(db.chapterUpdateHistoryTable)..addColumns([countExp]);
    final existingCount = await countQuery.map((row) => row.read(countExp)).getSingle();

    if (existingCount == 0) {
      final legacyJson = prefs.getString('hon_chapter_updates_v1');
      if (legacyJson != null && legacyJson.isNotEmpty) {
        try {
          final list = (jsonDecode(legacyJson) as List).whereType<Map>().toList();
          await db.batch((batch) {
            for (final item in list) {
              final bId = item['bookId']?.toString();
              final cId = item['chapterId']?.toString();
              final title = item['title']?.toString() ?? 'Chapter';
              final detectedStr = item['detectedAt']?.toString();
              final dt = detectedStr != null ? DateTime.tryParse(detectedStr) : null;
              if (bId != null && cId != null && dt != null) {
                batch.insert(
                  db.chapterUpdateHistoryTable,
                  ChapterUpdateHistoryTableCompanion.insert(
                    id: '$bId:$cId',
                    bookId: bId,
                    chapterId: cId,
                    title: title,
                    detectedAt: dt,
                  ),
                  mode: drift.InsertMode.insertOrReplace,
                );
              }
            }
          });
        } catch (e) {
          logIgnored(e, 'chapter_update_service');
        }
      }
    }

    // Load from Drift
    final rows = await (db.select(db.chapterUpdateHistoryTable)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.detectedAt)])
          ..limit(2000))
        .get();

    history = rows
        .map((r) => {
              'bookId': r.bookId,
              'chapterId': r.chapterId,
              'title': r.title,
              'detectedAt': r.detectedAt.toIso8601String(),
            })
        .toList();

    lastCheck = DateTime.tryParse(
      prefs.getString('hon_chapter_updates_checked') ?? '',
    );
  }

  static String normalizeTitle(String s) {
    var lower = s.toLowerCase().trim();
    // Normalize chapter abbreviations e.g. "chapter 1", "chap. 1", "ch 1" -> "c1"
    lower = lower.replaceAllMapped(
      RegExp(r'\b(?:chapter|chap|ch)\.?\s*(\d+)', unicode: true),
      (m) => 'c${m.group(1)}',
    );
    return lower.replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
  }

  String _normalizeTitle(String s) => normalizeTitle(s);

  static bool areTitlesSimilar(String t1, String t2) {
    final norm1 = t1.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
    final norm2 = t2.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
    if (norm1.isEmpty && norm2.isEmpty) return true;
    if (norm1.isEmpty || norm2.isEmpty) return false;
    if (norm1 == norm2) return true;

    final nums1 = RegExp(r'\d+').allMatches(norm1).map((m) => m.group(0)).toSet();
    final nums2 = RegExp(r'\d+').allMatches(norm2).map((m) => m.group(0)).toSet();
    if (nums1.isNotEmpty && nums2.isNotEmpty && nums1.intersection(nums2).isEmpty) {
      return false;
    }

    final tokens1 = norm1.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final tokens2 = norm2.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    if (tokens1.isEmpty || tokens2.isEmpty) return false;

    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);
    final jaccard = intersection.length / union.length;
    if (jaccard >= 0.5) return true;

    if (nums1.isNotEmpty && nums2.isNotEmpty && nums1.intersection(nums2).isNotEmpty) {
      if (intersection.isNotEmpty &&
          (intersection.length >= tokens1.length / 2 ||
              intersection.length >= tokens2.length / 2)) {
        return true;
      }
    }

    if (norm1.length > 3 && norm2.length > 3) {
      final dist = _levenshtein(norm1, norm2);
      final maxLen = math.max(norm1.length, norm2.length);
      if (dist / maxLen <= 0.3) return true;
    }

    return false;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var v0 = List<int>.generate(b.length + 1, (i) => i);
    var v1 = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (var j = 0; j <= b.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[b.length];
  }

  Future<int> check({Book? only}) async {
    if (checking) return 0;
    checking = true;
    errors.clear();
    unresolvedChaptersByBook.clear();
    notifyListeners();
    var added = 0;
    final db = DatabaseService.instance;

    try {
      await init();
      final books = (only == null ? db.getLibraryBooks() : [only])
          .where((book) => book.format == BookFormat.webNovel)
          .toList();

      if (books.isEmpty) return 0;

      // Concurrency controller: max 2 concurrent novel checks globally, strictly 1 per source
      final sourceQueues = <String, List<Book>>{};
      for (final book in books) {
        final s = book.sourceId ?? 'unknown';
        sourceQueues.putIfAbsent(s, () => []).add(book);
      }
      final activeSources = <String>{};
      var activeWorkers = 0;
      const maxGlobalConcurrent = 2;
      final completer = Completer<void>();

      Future<void> checkOneBook(Book book) async {
        try {
          final source = book.sourceId;
          if (source == null) {
            throw StateError(
              'Source information is missing. Open this novel in Browse first.',
            );
          }
          final novelId = book.sourceNovelId ??
              (book.id.startsWith('$source:') ? book.id.substring(source.length + 1) : null);
          if (novelId == null) {
            throw StateError(
              'Novel link is missing. Open this novel in Browse once.',
            );
          }

          final details = await (fetch?.call(source, novelId) ??
              SourceRegistry.instance.getNovelDetails(source, novelId));

          await db.ensureChaptersLoaded(book.id);
          final previousProgress = db.getProgress(book.id);
          final previousChapters = db.getChapters(book.id);
          final previousChapter = previousChapters
                  .where((c) => c.id == previousProgress?.lastChapterId)
                  .firstOrNull ??
              (previousProgress != null && previousChapters.isNotEmpty
                  ? previousChapters[previousProgress.chapterIndex.toInt().clamp(0, previousChapters.length - 1)]
                  : null);

          final oldList = List<Chapter>.from(previousChapters);
          final isInitialCheck = oldList.isEmpty;
          final remainingOld = List<Chapter>.from(oldList);
          final repairedIdMap = <String, String>{}; // oldId -> newId

          final now = DateTime.now();
          final chapters = <Chapter>[];
          final newHistoryEntries = <Map<String, dynamic>>[];

          // Count normalized title occurrences across all incoming chapters
          final incomingTitleCounts = <String, int>{};
          for (final ch in details.chapters) {
            final norm = _normalizeTitle(ch.title);
            if (norm.isNotEmpty) {
              incomingTitleCounts[norm] = (incomingTitleCounts[norm] ?? 0) + 1;
            }
          }

          // Count normalized title occurrences across all remaining old chapters
          final oldTitleCounts = <String, int>{};
          for (final ch in remainingOld) {
            final norm = _normalizeTitle(ch.title);
            if (norm.isNotEmpty) {
              oldTitleCounts[norm] = (oldTitleCounts[norm] ?? 0) + 1;
            }
          }

          // Pass 1: exact sourceChapterId match
          final matchedOldByIncoming = <int, Chapter>{};
          for (var i = 0; i < details.chapters.length; i++) {
            final incoming = details.chapters[i];
            final idx = remainingOld.indexWhere((c) => c.sourceChapterId == incoming.id);
            if (idx >= 0) {
              matchedOldByIncoming[i] = remainingOld.removeAt(idx);
            }
          }

          // Pass 2: normalized title match for remaining (ONLY if uniquely matched on BOTH sides)
          for (var i = 0; i < details.chapters.length; i++) {
            if (matchedOldByIncoming.containsKey(i)) continue;
            final incoming = details.chapters[i];
            final normIncoming = _normalizeTitle(incoming.title);
            if (normIncoming.isNotEmpty &&
                incomingTitleCounts[normIncoming] == 1 &&
                oldTitleCounts[normIncoming] == 1) {
              final matchingOld = remainingOld
                  .where((c) => _normalizeTitle(c.title) == normIncoming)
                  .toList();
              if (matchingOld.length == 1) {
                final old = matchingOld.first;
                remainingOld.remove(old);
                matchedOldByIncoming[i] = old;
              }
            }
          }

          // Note: Positional/fuzzy matching is eliminated to prevent transferring
          // unrelated downloaded files to replacement chapters at the same index.

          for (var i = 0; i < details.chapters.length; i++) {
            final incoming = details.chapters[i];
            final matchedOld = matchedOldByIncoming[i];

            Chapter chapter;
            if (matchedOld != null) {
              chapter = matchedOld.copyWith(
                sourceChapterId: incoming.id,
                title: incoming.title,
                url: incoming.url ?? incoming.id,
                chapterIndex: i.toDouble(),
                releaseDate: incoming.releaseDate ?? matchedOld.releaseDate,
                updatedAt: now,
              );
              if (matchedOld.id != chapter.id) {
                repairedIdMap[matchedOld.id] = chapter.id;
              }
              final oldKey = '${book.id}:${matchedOld.sourceChapterId}';
              if (matchedOld.sourceChapterId.isNotEmpty && oldKey != chapter.id) {
                repairedIdMap[oldKey] = chapter.id;
              }
            } else {
              // Brand new chapter
              chapter = Chapter(
                id: '${book.id}:${incoming.id}',
                bookId: book.id,
                sourceChapterId: incoming.id,
                title: incoming.title,
                chapterIndex: i.toDouble(),
                url: incoming.url ?? incoming.id,
                releaseDate: incoming.releaseDate,
                updatedAt: now,
              );

              // Do NOT mark all chapters as new on the initial check (B4)
              if (!isInitialCheck) {
                added++;
                newHistoryEntries.add({
                  'bookId': book.id,
                  'chapterId': chapter.id,
                  'title': chapter.title,
                  'detectedAt': now.toIso8601String(),
                });
              }
            }
            chapters.add(chapter);
          }

          // Retain remaining old chapters (e.g. removed upstream or healed)
          if (remainingOld.isNotEmpty) {
            unresolvedChaptersByBook[book.id] = List.unmodifiable(remainingOld);
            for (final retained in remainingOld) {
              chapters.add(
                retained.copyWith(chapterIndex: chapters.length.toDouble()),
              );
            }
          }

          await db.saveChapters(book.id, chapters);

          // Update reading progress lastChapterId if healed or shifted
          if (previousProgress != null) {
            var updatedProgress = previousProgress;
            var needsProgressUpdate = false;

            if (previousProgress.lastChapterId != null &&
                repairedIdMap.containsKey(previousProgress.lastChapterId)) {
              final healedId = repairedIdMap[previousProgress.lastChapterId]!;
              final pos = chapters.indexWhere((c) => c.id == healedId);
              updatedProgress = updatedProgress.copyWith(
                lastChapterId: healedId,
                chapterIndex: pos >= 0 ? pos.toDouble() : updatedProgress.chapterIndex,
              );
              needsProgressUpdate = true;
            } else if (previousChapter != null) {
              final pos = chapters.indexWhere((c) => c.id == previousChapter.id);
              if (pos >= 0 && pos != previousProgress.chapterIndex.toInt()) {
                updatedProgress = updatedProgress.copyWith(chapterIndex: pos.toDouble());
                needsProgressUpdate = true;
              }
            }

            if (needsProgressUpdate) {
              await db.saveProgress(updatedProgress);
            }
          }

          // Persist update history to Drift table and in-memory list
          if (newHistoryEntries.isNotEmpty) {
            final appDb = db.db;
            await appDb.batch((batch) {
              for (final item in newHistoryEntries) {
                batch.insert(
                  appDb.chapterUpdateHistoryTable,
                  ChapterUpdateHistoryTableCompanion.insert(
                    id: '${item['bookId']}:${item['chapterId']}',
                    bookId: item['bookId'] as String,
                    chapterId: item['chapterId'] as String,
                    title: item['title'] as String,
                    detectedAt: DateTime.parse(item['detectedAt'] as String),
                  ),
                  mode: drift.InsertMode.insertOrReplace,
                );
              }
            });
            for (final item in newHistoryEntries) {
              history.insert(0, item);
            }
          }

          await db.saveBook(
            book.copyWith(
              totalChapters: chapters.length,
              sourceNovelId: novelId,
              updatedAt: now,
            ),
          );
        } catch (error) {
          errors[book.id] = '$error';
        }
        notifyListeners();
      }

      void tryDispatch() {
        while (activeWorkers < maxGlobalConcurrent) {
          String? availableSource;
          for (final entry in sourceQueues.entries) {
            if (!activeSources.contains(entry.key) && entry.value.isNotEmpty) {
              availableSource = entry.key;
              break;
            }
          }
          if (availableSource == null) break;

          final book = sourceQueues[availableSource]!.removeAt(0);
          activeSources.add(availableSource);
          activeWorkers++;

          checkOneBook(book).whenComplete(() {
            activeWorkers--;
            activeSources.remove(availableSource);
            tryDispatch();
            if (activeWorkers == 0 && sourceQueues.values.every((q) => q.isEmpty)) {
              if (!completer.isCompleted) completer.complete();
            }
          });
        }
        if (activeWorkers == 0 && sourceQueues.values.every((q) => q.isEmpty)) {
          if (!completer.isCompleted) completer.complete();
        }
      }

      tryDispatch();
      await completer.future;

      // Keep one history row per chapter across repeated checks, up to 2000
      final seen = <String>{};
      history = history
          .where((item) => seen.add('${item['bookId']}:${item['chapterId']}'))
          .take(2000)
          .toList();

      final prefs = await SharedPreferences.getInstance();
      lastCheck = DateTime.now();
      await prefs.setString('hon_chapter_updates_v1', jsonEncode(history));
      await prefs.setString(
        'hon_chapter_updates_checked',
        lastCheck!.toIso8601String(),
      );

      return added;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    history = [];
    final db = DatabaseService.instance.db;
    await db.delete(db.chapterUpdateHistoryTable).go();
    await (await SharedPreferences.getInstance()).remove(
      'hon_chapter_updates_v1',
    );
    notifyListeners();
  }
}
