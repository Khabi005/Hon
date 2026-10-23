import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database/database_service.dart';
import '../models/highlight.dart';
import '../models/reading_progress.dart';
import '../utils/reading_time.dart';

class ReadiumOpenResult {
  final bool success;
  final bool cancelled;
  final bool launched;
  final String filePath;
  final int initialChapterIndex;
  final String? initialLocator;
  final String engine;
  final String? errorCode;
  final String? errorMessage;

  const ReadiumOpenResult({
    required this.success,
    this.cancelled = false,
    this.launched = false,
    required this.filePath,
    required this.initialChapterIndex,
    this.initialLocator,
    required this.engine,
    this.errorCode,
    this.errorMessage,
  });
}

class ReadiumReaderService {
  static const MethodChannel _channel = MethodChannel(
    'com.hon.reader/readium_reader',
  );
  static bool _initialized = false;

  // Multi-book pending persistence map
  static final Map<String, ReadingProgress> _pendingByBook = {};
  static final Map<String, DateTime> _firstPendingTimeByBook = {};
  static Timer? _debounceTimer;

  // Request & Session Tracking
  static final Set<String> _openingRequests = {};
  static String? _activeRequestId;

  static bool _isCurrentSession(Map<dynamic, dynamic> args) {
    final requestId = args['requestId'] as String?;
    // Native events always include an ID. Once a session closes, its late
    // callbacks must never revive a timer or show a stale error.
    return requestId == null ||
        requestId.isEmpty ||
        requestId == _activeRequestId;
  }

  @visibleForTesting
  static void setActiveRequestIdForTesting(String? requestId) {
    _activeRequestId = requestId;
  }

  static final ValueNotifier<String?> lastErrorNotifier =
      ValueNotifier<String?>(null);
  static final ValueNotifier<String?> persistenceErrorNotifier =
      ValueNotifier<String?>(null);
  static void Function(String bookId, String code, String message)?
  onErrorCallback;
  static void Function(String bookId)? onReadyCallback;
  static void Function(String bookId, double totalProgression)?
  onClosedCallback;
  static void Function(String? bookId, String theme, bool scroll, double fontSize)?
  onPreferencesChanged;
  static void Function(String? bookId, Map<String, dynamic> typography)? onTypographyChanged;

  // Active foreground session time tracking
  static DateTime? _activeSessionStartTime;
  // Last page turn or scroll the native reader reported.
  static DateTime? _lastReadingActivity;
  static bool _isForegrounded = true;
  static bool _isReady = false;

  @visibleForTesting
  static DateTime? get activeSessionStartTime => _activeSessionStartTime;

  @visibleForTesting
  static set activeSessionStartTime(DateTime? val) =>
      _activeSessionStartTime = val;

  /// Locator changes keep the session counting. After a long idle gap the
  /// counted part is banked and a new session starts now.
  static void _noteReadingActivity() {
    final now = DateTime.now();
    final start = _activeSessionStartTime;
    if (start != null && readingWentIdle(start, _lastReadingActivity, now)) {
      final elapsed = countedReadingSeconds(start, _lastReadingActivity, now);
      if (elapsed > 0) DatabaseService.instance.addReadingTime(elapsed);
      _activeSessionStartTime = now;
    }
    _lastReadingActivity = now;
  }

  @visibleForTesting
  static bool get isForegrounded => _isForegrounded;

  @visibleForTesting
  static set isForegrounded(bool val) => _isForegrounded = val;

  static bool get isAndroidNativeSupported => Platform.isAndroid;

  /// Ensures native-to-Dart locator updates are handled and persisted with bounded debounced disk I/O
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'getReaderBookmarks':
          final args = call.arguments as Map<dynamic, dynamic>?;
          final bookId = args?['bookId'] as String?;
          if (bookId == null) return <Map<String, dynamic>>[];
          return DatabaseService.instance
              .getBookmarks(bookId)
              .map((bookmark) => bookmark.toMap())
              .toList();

        case 'toggleReaderBookmark':
          final args = call.arguments as Map<dynamic, dynamic>?;
          final bookId = args?['bookId'] as String?;
          final chapter = args?['chapterIndex'] as int?;
          if (bookId == null || chapter == null) return false;
          return DatabaseService.instance.toggleBookmark(
            bookId,
            chapter,
            label: args?['title'] as String? ?? args?['label'] as String?,
            snippet: args?['snippet'] as String?,
            locatorString: args?['locator'] as String? ?? args?['locatorString'] as String?,
            locatorVersion: args?['locatorVersion'] as String? ?? 'readium-v2',
          );

        case 'getReaderHighlights': {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final bookId = args?['bookId'] as String?;
          if (bookId == null) return <Map<String, dynamic>>[];
          return DatabaseService.instance
              .getHighlights(bookId)
              .map((h) => h.toMap())
              .toList();
        }

        case 'saveReaderHighlight': {
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args == null) return false;
          final map = Map<String, dynamic>.from(args);
          final highlight = Highlight(
            id: map['id'] as String? ?? 'hl_${DateTime.now().millisecondsSinceEpoch}',
            bookId: map['bookId'] as String? ?? '',
            locatorString: map['locator'] as String? ?? map['locatorString'] as String? ?? '',
            selectedText: map['selectedText'] as String? ?? '',
            color: map['color'] as String? ?? 'yellow',
            note: map['note'] as String?,
            createdAt: map['createdAt'] != null
                ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
                : DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await DatabaseService.instance.saveHighlight(highlight);
          return true;
        }

        case 'deleteReaderHighlight': {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final id = args?['id'] as String?;
          if (id != null && id.isNotEmpty) {
            await DatabaseService.instance.deleteHighlight(id);
            return true;
          }
          return false;
        }

        case 'getBookReaderSettings': {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final bookId = args?['bookId'] as String?;
          if (bookId == null) return null;
          return DatabaseService.instance.getBookReaderSettings(bookId);
        }

        case 'saveBookReaderSettings': {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final bookId = args?['bookId'] as String?;
          final settings = args?['settings'] as Map<dynamic, dynamic>?;
          if (bookId != null && settings != null) {
            await DatabaseService.instance.saveBookReaderSettings(
              bookId,
              Map<String, dynamic>.from(settings),
            );
            return true;
          }
          return false;
        }

        case 'resetBookReaderSettings': {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final bookId = args?['bookId'] as String?;
          if (bookId != null) {
            await DatabaseService.instance.resetBookReaderSettings(bookId);
            return true;
          }
          return false;
        }

        case 'onReaderPreferencesChanged':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null) {
            final bookId = args['bookId'] as String?;
            if (args['typography'] is Map) {
              onTypographyChanged?.call(
                bookId,
                Map<String, dynamic>.from(args['typography'] as Map),
              );
            }
            onPreferencesChanged?.call(
              bookId,
              args['theme'] as String? ?? 'calm',
              args['isScroll'] as bool? ?? false,
              (args['fontSize'] as num?)?.toDouble() ?? 1.0,
            );
          }
          break;
        case 'onLocatorChanged':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && _isCurrentSession(args)) {
            _noteReadingActivity();
            final bookId = args['bookId'] as String?;
            final locatorJson = args['locator'] as String?;
            // Whole-book total progression (0.0 - 1.0)
            final progression =
                (args['totalProgression'] as num?)?.toDouble() ??
                (args['progression'] as num?)?.toDouble() ??
                0.0;

            if (bookId != null && bookId.isNotEmpty) {
              final existing = DatabaseService.instance.getProgress(bookId);
              final updated =
                  (existing ??
                          ReadingProgress(
                            bookId: bookId,
                            lastReadAt: DateTime.now(),
                          ))
                      .copyWith(
                        locatorString: locatorJson,
                        locatorVersion: 'readium-v1',
                        completionPercentage: progression.clamp(0.0, 1.0),
                        lastReadAt: DateTime.now(),
                      );

              _schedulePendingProgress(bookId, updated);
            }
          }
          break;

        case 'onReaderReady':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && _isCurrentSession(args)) {
            final bookId = args['bookId'] as String? ?? '';
            final reqId = args['requestId'] as String? ?? '';
            _openingRequests.remove(reqId);
            _isReady = true;
            final isFg = (args['isForegrounded'] as bool?) ?? true;
            _isForegrounded = isFg;

            // Timer starts ONLY if both readable content is ready AND the reader is foregrounded!
            if (isFg && _activeSessionStartTime == null) {
              _activeSessionStartTime = DateTime.now();
            } else if (!isFg) {
              _activeSessionStartTime = null;
            }

            lastErrorNotifier.value = null;
            onReadyCallback?.call(bookId);

            debugPrint('[Readium] ready request=$reqId book=$bookId');
          }
          break;

        case 'onReaderError':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && _isCurrentSession(args)) {
            final bookId = args['bookId'] as String? ?? '';
            final reqId = args['requestId'] as String? ?? '';
            final code = args['code'] as String? ?? 'UNKNOWN_ERROR';
            final message =
                args['message'] as String? ?? 'An error occurred in Readium';
            // Clear timer on error: error screen must not accumulate reading time!
            _isReady = false;
            _isForegrounded = false;
            _activeSessionStartTime = null;
            lastErrorNotifier.value = '$code: $message';
            if (!_openingRequests.remove(reqId)) {
              onErrorCallback?.call(bookId, code, message);
            }
            debugPrint(
              '[Readium] error request=$reqId book=$bookId code=$code',
            );
          }
          break;

        case 'onReaderPaused':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && _isCurrentSession(args)) {
            final bookId = args['bookId'] as String? ?? '';
            final locatorJson = args['locator'] as String?;
            final progression =
                (args['totalProgression'] as num?)?.toDouble() ??
                (args['progression'] as num?)?.toDouble();

            _isForegrounded = false;
            // Save elapsed foreground reading time and STOP timer!
            // Crucial: do NOT leave timer running in the background!
            if (_activeSessionStartTime != null) {
              final elapsed = countedReadingSeconds(
                _activeSessionStartTime!,
                _lastReadingActivity,
                DateTime.now(),
              );
              if (elapsed > 0) {
                DatabaseService.instance.addReadingTime(elapsed);
              }
              _activeSessionStartTime = null;
            }

            if (bookId.isNotEmpty &&
                locatorJson != null &&
                locatorJson.trim().isNotEmpty) {
              final existing = DatabaseService.instance.getProgress(bookId);
              final updated =
                  (existing ??
                          ReadingProgress(
                            bookId: bookId,
                            lastReadAt: DateTime.now(),
                          ))
                      .copyWith(
                        locatorString: locatorJson,
                        locatorVersion: 'readium-v1',
                        completionPercentage:
                            (progression ??
                                    existing?.completionPercentage ??
                                    0.0)
                                .clamp(0.0, 1.0),
                        lastReadAt: DateTime.now(),
                      );

              // On pause, immediately flush progress to disk!
              _pendingByBook[bookId] = updated;
              await _flushBook(bookId);
            }
          }
          break;

        case 'onReaderResumed':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && _isCurrentSession(args)) {
            // Restart timer only when reader returns to the foreground with readable content
            _isForegrounded = true;
            if (_isReady && _activeSessionStartTime == null) {
              _activeSessionStartTime = DateTime.now();
            }
          }
          break;

        case 'onReaderClosed':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && _isCurrentSession(args)) {
            final reqId = args['requestId'] as String? ?? '';
            _openingRequests.remove(reqId);
            _isReady = false;
            if (reqId.isNotEmpty && reqId == _activeRequestId) {
              _activeRequestId = null;
            }
            final bookId = args['bookId'] as String? ?? '';
            final locatorJson = args['locator'] as String?;
            final progression = (args['totalProgression'] as num?)?.toDouble();

            _isForegrounded = false;
            // Accumulate any remaining reading time before closing
            if (_activeSessionStartTime != null) {
              final elapsed = countedReadingSeconds(
                _activeSessionStartTime!,
                _lastReadingActivity,
                DateTime.now(),
              );
              if (elapsed > 0) {
                DatabaseService.instance.addReadingTime(elapsed);
              }
              _activeSessionStartTime = null;
            }

            if (bookId.isNotEmpty) {
              final existing = DatabaseService.instance.getProgress(bookId);

              // If no valid new locator exists (e.g. error on opening, or closed before reading),
              // leave the saved reading progress untouched!
              if (locatorJson == null || locatorJson.trim().isEmpty) {
                onClosedCallback?.call(
                  bookId,
                  existing?.completionPercentage ?? 0.0,
                );
                break;
              }

              final updated =
                  (existing ??
                          ReadingProgress(
                            bookId: bookId,
                            lastReadAt: DateTime.now(),
                          ))
                      .copyWith(
                        locatorString: locatorJson,
                        locatorVersion: 'readium-v1',
                        completionPercentage:
                            (progression ??
                                    existing?.completionPercentage ??
                                    0.0)
                                .clamp(0.0, 1.0),
                        lastReadAt: DateTime.now(),
                      );

              // Immediately flush this book to disk without waiting for any timer!
              _pendingByBook[bookId] = updated;
              await _flushBook(bookId);
              onClosedCallback?.call(bookId, updated.completionPercentage);
            }
          }
          break;
      }
    });
  }

  static void _schedulePendingProgress(
    String bookId,
    ReadingProgress progress,
  ) {
    _pendingByBook[bookId] = progress;
    final firstTime = _firstPendingTimeByBook.putIfAbsent(
      bookId,
      () => DateTime.now(),
    );

    // Bounded saving: If updates continue without pause for >= 3 seconds, force flush immediately!
    if (DateTime.now().difference(firstTime).inSeconds >= 3) {
      _flushBook(bookId);
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _flushAll();
    });
  }

  static Future<bool> _flushBook(String bookId) async {
    final prog = _pendingByBook[bookId];
    if (prog == null) return true;

    try {
      await DatabaseService.instance.saveProgress(prog);
      // Only remove from pending after successful disk write!
      if (_pendingByBook[bookId] == prog) {
        _pendingByBook.remove(bookId);
        _firstPendingTimeByBook.remove(bookId);
      }
      persistenceErrorNotifier.value = null;
      return true;
    } catch (e) {
      // Keep failed progress pending in _pendingByBook so retry or subsequent flushes can save it!
      final errMsg = 'Failed to persist reading progress for book $bookId: $e';
      persistenceErrorNotifier.value = errMsg;
      debugPrint('[ReadiumReaderService] $errMsg');
      return false;
    }
  }

  static Future<bool> _flushAll() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    final bookIds = _pendingByBook.keys.toList();
    bool allSuccess = true;
    for (final bId in bookIds) {
      final success = await _flushBook(bId);
      if (!success) allSuccess = false;
    }
    return allSuccess;
  }

  static Future<bool> isPlatformSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isPlatformSupported');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<ReadiumOpenResult?> openEpub({
    required String filePath,
    required String bookId,
    required String title,
    int chapterIndex = 0,
    String? initialLocator,
  }) async {
    if (!Platform.isAndroid) return null;
    initialize();

    // Flush any pending books before opening a new book/session
    await _flushAll();

    final requestId = '${bookId}_${DateTime.now().microsecondsSinceEpoch}';
    _activeRequestId = requestId;
    _isReady = false;
    _activeSessionStartTime = null;
    _openingRequests.add(requestId);
    Timer(const Duration(minutes: 1), () => _openingRequests.remove(requestId));

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('openEpub', {
        'filePath': filePath,
        'bookId': bookId,
        'title': title,
        'chapterIndex': chapterIndex,
        'initialLocator': initialLocator,
        'requestId': requestId,
      });

      return ReadiumOpenResult(
        success: res?['success'] == true,
        cancelled: res?['cancelled'] == true,
        launched: res?['launched'] == true,
        filePath: filePath,
        initialChapterIndex: chapterIndex,
        initialLocator: initialLocator,
        engine: 'Readium/Android-Native',
        errorCode: res?['errorCode'] as String?,
        errorMessage: res?['errorMessage'] as String?,
      );
    } on PlatformException catch (pe) {
      return ReadiumOpenResult(
        success: false,
        filePath: filePath,
        initialChapterIndex: chapterIndex,
        engine: 'Readium/Android-Native',
        errorCode: pe.code,
        errorMessage: pe.message,
      );
    } catch (e) {
      return ReadiumOpenResult(
        success: false,
        filePath: filePath,
        initialChapterIndex: chapterIndex,
        engine: 'Readium/Android-Native',
        errorCode: 'EXCEPTION',
        errorMessage: e.toString(),
      );
    } finally {
      // The native result is delivered before its matching lifecycle event.
      // Keep the request marked as opening until that event consumes it so a
      // launch failure cannot also produce a second global error notification.
      if (_activeRequestId != requestId) {
        _openingRequests.remove(requestId);
      }
    }
  }

  static Future<void> saveLocator({
    required String locator,
    required int chapterIndex,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('saveLocator', {
        'locator': locator,
        'chapterIndex': chapterIndex,
      });
    } catch (_) {}
  }

  static Future<void> applySettings({
    required double fontSize,
    required String theme,
    required bool isScroll,
    bool? isGlass,
    Map<String, dynamic>? typography,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('applySettings', {
        'fontSize': fontSize,
        'theme': theme,
        'isScroll': isScroll,
        'isGlass': ?isGlass,
        'typography': ?typography,
      });
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> closeSession() async {
    await _flushAll();
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMapMethod<String, dynamic>('closeSession');
    } catch (_) {
      return null;
    }
  }
}
