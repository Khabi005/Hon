import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database/database_service.dart';
import '../models/reading_progress.dart';

class ReadiumOpenResult {
  final bool success;
  final bool launched;
  final String filePath;
  final int initialChapterIndex;
  final String? initialLocator;
  final String engine;
  final String? errorCode;
  final String? errorMessage;

  const ReadiumOpenResult({
    required this.success,
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
  static const MethodChannel _channel = MethodChannel('com.hon.reader/readium_reader');
  static bool _initialized = false;

  // Multi-book pending persistence map
  static final Map<String, ReadingProgress> _pendingByBook = {};
  static final Map<String, DateTime> _firstPendingTimeByBook = {};
  static Timer? _debounceTimer;

  // Request & Session Tracking
  static final Map<String, Completer<ReadiumOpenResult>> _pendingRequests = {};
  static final ValueNotifier<String?> lastErrorNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> persistenceErrorNotifier = ValueNotifier<String?>(null);
  static void Function(String bookId, String code, String message)? onErrorCallback;
  static void Function(String bookId)? onReadyCallback;
  static void Function(String bookId, double totalProgression)? onClosedCallback;

  // Active foreground session time tracking
  static DateTime? _activeSessionStartTime;

  static bool get isAndroidNativeSupported => Platform.isAndroid;

  /// Ensures native-to-Dart locator updates are handled and persisted with bounded debounced disk I/O
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onLocatorChanged':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null) {
            final bookId = args['bookId'] as String?;
            final locatorJson = args['locator'] as String?;
            // Whole-book total progression (0.0 - 1.0)
            final progression = (args['totalProgression'] as num?)?.toDouble() ??
                (args['progression'] as num?)?.toDouble() ??
                0.0;

            if (bookId != null && bookId.isNotEmpty) {
              final existing = DatabaseService.instance.getProgress(bookId);
              final updated = (existing ?? ReadingProgress(
                bookId: bookId,
                lastReadAt: DateTime.now(),
              )).copyWith(
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
          if (args != null) {
            final bookId = args['bookId'] as String? ?? '';
            final reqId = args['requestId'] as String? ?? '';
            _activeSessionStartTime = DateTime.now();
            lastErrorNotifier.value = null;
            onReadyCallback?.call(bookId);

            final completer = _pendingRequests.remove(reqId) ?? _pendingRequests.remove(bookId);
            if (completer != null && !completer.isCompleted) {
              completer.complete(const ReadiumOpenResult(
                success: true,
                launched: true,
                filePath: '',
                initialChapterIndex: 0,
                engine: 'Readium/Android-Native',
              ));
            }
          }
          break;

        case 'onReaderError':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null) {
            final bookId = args['bookId'] as String? ?? '';
            final reqId = args['requestId'] as String? ?? '';
            final code = args['code'] as String? ?? 'UNKNOWN_ERROR';
            final message = args['message'] as String? ?? 'An error occurred in Readium';
            lastErrorNotifier.value = '$code: $message';
            onErrorCallback?.call(bookId, code, message);

            final completer = _pendingRequests.remove(reqId) ?? _pendingRequests.remove(bookId);
            if (completer != null && !completer.isCompleted) {
              completer.complete(ReadiumOpenResult(
                success: false,
                launched: true,
                filePath: '',
                initialChapterIndex: 0,
                engine: 'Readium/Android-Native',
                errorCode: code,
                errorMessage: message,
              ));
            }
          }
          break;

        case 'onReaderPaused':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null) {
            final bookId = args['bookId'] as String? ?? '';
            final locatorJson = args['locator'] as String?;
            final progression = (args['totalProgression'] as num?)?.toDouble() ??
                (args['progression'] as num?)?.toDouble();

            // Accumulate active foreground reading time
            if (_activeSessionStartTime != null) {
              final elapsed = DateTime.now().difference(_activeSessionStartTime!).inSeconds;
              if (elapsed > 0) {
                DatabaseService.instance.addReadingTime(elapsed);
              }
              _activeSessionStartTime = DateTime.now();
            }

            if (bookId.isNotEmpty && locatorJson != null && locatorJson.trim().isNotEmpty) {
              final existing = DatabaseService.instance.getProgress(bookId);
              final updated = (existing ?? ReadingProgress(
                bookId: bookId,
                lastReadAt: DateTime.now(),
              )).copyWith(
                locatorString: locatorJson,
                locatorVersion: 'readium-v1',
                completionPercentage: (progression ?? existing?.completionPercentage ?? 0.0).clamp(0.0, 1.0),
                lastReadAt: DateTime.now(),
              );

              // On pause, immediately flush progress to disk!
              _pendingByBook[bookId] = updated;
              await _flushBook(bookId);
            }
          }
          break;

        case 'onReaderClosed':
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null) {
            final bookId = args['bookId'] as String? ?? '';
            final locatorJson = args['locator'] as String?;
            final progression = (args['totalProgression'] as num?)?.toDouble();

            // Accumulate any remaining reading time before closing
            if (_activeSessionStartTime != null) {
              final elapsed = DateTime.now().difference(_activeSessionStartTime!).inSeconds;
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
                onClosedCallback?.call(bookId, existing?.completionPercentage ?? 0.0);
                break;
              }

              final updated = (existing ?? ReadingProgress(
                bookId: bookId,
                lastReadAt: DateTime.now(),
              )).copyWith(
                locatorString: locatorJson,
                locatorVersion: 'readium-v1',
                completionPercentage: (progression ?? existing?.completionPercentage ?? 0.0).clamp(0.0, 1.0),
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

  static void _schedulePendingProgress(String bookId, ReadingProgress progress) {
    _pendingByBook[bookId] = progress;
    final firstTime = _firstPendingTimeByBook.putIfAbsent(bookId, () => DateTime.now());

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

    final requestId = '${bookId}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<ReadiumOpenResult>();
    _pendingRequests[requestId] = completer;

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('openEpub', {
        'filePath': filePath,
        'bookId': bookId,
        'title': title,
        'chapterIndex': chapterIndex,
        'initialLocator': initialLocator,
        'requestId': requestId,
      });

      if (res == null || res['success'] != true) {
        _pendingRequests.remove(requestId);
        return ReadiumOpenResult(
          success: false,
          filePath: filePath,
          initialChapterIndex: chapterIndex,
          engine: 'Readium/Android-Native',
          errorCode: 'OPEN_FAILED',
          errorMessage: 'Native bridge launch returned false or null',
        );
      }

      // Await onReaderReady or onReaderError from ReadiumReaderActivity (with timeout)
      try {
        final readyResult = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            // Never infer readiness from elapsed time! Return explicit timeout error.
            return ReadiumOpenResult(
              success: false,
              launched: true,
              filePath: filePath,
              initialChapterIndex: chapterIndex,
              initialLocator: initialLocator,
              engine: 'Readium/Android-Native',
              errorCode: 'TIMEOUT',
              errorMessage: 'Timed out waiting for Readium reader ready signal (15s)',
            );
          },
        );
        return readyResult;
      } finally {
        _pendingRequests.remove(requestId);
      }
    } on PlatformException catch (pe) {
      _pendingRequests.remove(requestId);
      return ReadiumOpenResult(
        success: false,
        filePath: filePath,
        initialChapterIndex: chapterIndex,
        engine: 'Readium/Android-Native',
        errorCode: pe.code,
        errorMessage: pe.message,
      );
    } catch (e) {
      _pendingRequests.remove(requestId);
      return ReadiumOpenResult(
        success: false,
        filePath: filePath,
        initialChapterIndex: chapterIndex,
        engine: 'Readium/Android-Native',
        errorCode: 'EXCEPTION',
        errorMessage: e.toString(),
      );
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
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('applySettings', {
        'fontSize': fontSize,
        'theme': theme,
        'isScroll': isScroll,
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
