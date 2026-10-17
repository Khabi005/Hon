import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/reading_progress.dart';
import 'package:hon/core/native/readium_reader_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  const channel = MethodChannel('com.hon.reader/readium_reader');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = DatabaseService.instance;
    await db.init();
    ReadiumReaderService.initialize();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Phase 0A — Readium Native Bridge & Locator Sync', () {
    const bookId = 'book_readium_test';

    final testEpubBook = Book(
      id: bookId,
      title: 'Alice in Wonderland',
      author: 'Lewis Carroll',
      format: BookFormat.epub,
      filePath: '/mock/path/alice.epub',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('Method channel onLocatorChanged updates DatabaseService progress with debounce flush', () async {
      await db.saveBook(testEpubBook);
      expect(db.getProgress(bookId), isNull);

      const sampleLocatorJson = '{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.35,"totalProgression":0.12}}';

      final message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLocatorChanged', {
          'bookId': bookId,
          'locator': sampleLocatorJson,
          'progression': 0.35,
          'totalProgression': 0.12,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', message, (ByteData? reply) {});

      // Flush debounce write queue via closeSession
      await ReadiumReaderService.closeSession();

      final progress = db.getProgress(bookId);
      expect(progress, isNotNull);
      expect(progress!.locatorString, equals(sampleLocatorJson));
      expect(progress.locatorVersion, equals('readium-v1'));
      expect(progress.isReadiumLocator, isTrue);
      expect(progress.isDartLocator, isFalse);
      expect(progress.completionPercentage, closeTo(0.12, 0.001));
    });

    test('Multi-book rapid updates preserve positions independently without overwriting', () async {
      const bookA = 'book_a';
      const bookB = 'book_b';

      await db.saveBook(testEpubBook.copyWith(id: bookA, title: 'Book A'));
      await db.saveBook(testEpubBook.copyWith(id: bookB, title: 'Book B'));

      // Send update for Book A
      final msgA = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLocatorChanged', {
          'bookId': bookA,
          'locator': '{"href":"a1.xhtml"}',
          'totalProgression': 0.25,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', msgA, (ByteData? reply) {});

      // Immediately send update for Book B before debounce fires
      final msgB = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLocatorChanged', {
          'bookId': bookB,
          'locator': '{"href":"b1.xhtml"}',
          'totalProgression': 0.60,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', msgB, (ByteData? reply) {});

      // Flush both
      await ReadiumReaderService.closeSession();

      final progA = db.getProgress(bookA);
      final progB = db.getProgress(bookB);

      expect(progA, isNotNull);
      expect(progA!.completionPercentage, closeTo(0.25, 0.001));
      expect(progA.locatorString, equals('{"href":"a1.xhtml"}'));

      expect(progB, isNotNull);
      expect(progB!.completionPercentage, closeTo(0.60, 0.001));
      expect(progB.locatorString, equals('{"href":"b1.xhtml"}'));
    });

    test('onReaderClosed event instantly flushes position to disk without timer wait', () async {
      await db.saveBook(testEpubBook);

      final closeMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderClosed', {
          'bookId': bookId,
          'locator': '{"href":"final_chapter.xhtml"}',
          'totalProgression': 0.88,
        }),
      );

      // Deliver onReaderClosed: must flush synchronously into DatabaseService
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', closeMsg, (ByteData? reply) {});

      final progress = db.getProgress(bookId);
      expect(progress, isNotNull);
      expect(progress!.completionPercentage, closeTo(0.88, 0.001));
      expect(progress.locatorString, equals('{"href":"final_chapter.xhtml"}'));
    });

    test('onReaderError updates lastErrorNotifier and triggers error callback', () async {
      String? receivedCode;
      String? receivedMsg;

      ReadiumReaderService.onErrorCallback = (id, code, msg) {
        receivedCode = code;
        receivedMsg = msg;
      };

      final errorMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderError', {
          'bookId': bookId,
          'code': 'PARSE_ERROR',
          'message': 'Failed to parse EPUB container',
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', errorMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.lastErrorNotifier.value, contains('PARSE_ERROR'));
      expect(receivedCode, equals('PARSE_ERROR'));
      expect(receivedMsg, equals('Failed to parse EPUB container'));

      ReadiumReaderService.onErrorCallback = null;
    });

    test('ReadingProgress versioning distinguishes Readium and Dart locators', () {
      final readiumProgress = ReadingProgress(
        bookId: 'b1',
        locatorString: '{"href":"text/ch01.xhtml","locations":{"progression":0.5}}',
        lastReadAt: DateTime.now(),
      );
      expect(readiumProgress.isReadiumLocator, isTrue);
      expect(readiumProgress.isDartLocator, isFalse);

      final dartProgress = ReadingProgress(
        bookId: 'b2',
        locatorString: 'ch_intro#offset=342.0',
        lastReadAt: DateTime.now(),
      );
      expect(dartProgress.isReadiumLocator, isFalse);
      expect(dartProgress.isDartLocator, isTrue);

      final map = readiumProgress.toMap();
      final restored = ReadingProgress.fromMap(map);
      expect(restored.locatorVersion, equals('readium-v1'));
      expect(restored.isReadiumLocator, isTrue);
    });

    test('onReaderClosed with null or empty locator leaves existing reading progress untouched', () async {
      await db.saveBook(testEpubBook);
      // Pre-seed 72% reading progress
      await db.saveProgress(ReadingProgress(
        bookId: bookId,
        locatorString: '{"href":"chapter_7.xhtml"}',
        locatorVersion: 'readium-v1',
        completionPercentage: 0.72,
        lastReadAt: DateTime.now(),
      ));

      // Simulate failed reader launch or close before locator acquired: locator is null
      final failedCloseMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderClosed', {
          'bookId': bookId,
          'locator': null,
          'totalProgression': null,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', failedCloseMsg, (ByteData? reply) {});

      final progress = db.getProgress(bookId);
      expect(progress, isNotNull);
      // Progress MUST remain 72%, NOT reset to 0%!
      expect(progress!.completionPercentage, closeTo(0.72, 0.001));
      expect(progress.locatorString, equals('{"href":"chapter_7.xhtml"}'));
    });

    test('onReaderPaused event immediately flushes locator and progress to database', () async {
      await db.saveBook(testEpubBook);

      final pausedMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderPaused', {
          'bookId': bookId,
          'locator': '{"href":"paused_chapter.xhtml"}',
          'totalProgression': 0.45,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', pausedMsg, (ByteData? reply) {});

      final progress = db.getProgress(bookId);
      expect(progress, isNotNull);
      expect(progress!.completionPercentage, closeTo(0.45, 0.001));
      expect(progress.locatorString, equals('{"href":"paused_chapter.xhtml"}'));
    });

    test('openEpub gracefully handles non-Android platform or missing native host', () async {
      final res = await ReadiumReaderService.openEpub(
        filePath: '/mock/path/alice.epub',
        bookId: bookId,
        title: 'Alice in Wonderland',
      );
      expect(res, isNull);
    });

    test('Reading session lifecycle: start on ready -> stop on pause -> restart on resume -> clear on close (background time never counted)', () async {
      final initialMinutes = db.getTodayReadingMinutes();

      // 1. Reader becomes ready -> session timer starts
      final readyMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderReady', {
          'bookId': bookId,
          'requestId': 'req_time_test',
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', readyMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNotNull);

      // Simulate 60 seconds of active reading
      ReadiumReaderService.activeSessionStartTime =
          DateTime.now().subtract(const Duration(seconds: 60));

      // 2. Reader pauses -> flushes 60s and STOPS timer (null)
      final pausedMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderPaused', {
          'bookId': bookId,
          'locator': '{"href":"ch1.xhtml"}',
          'totalProgression': 0.1,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', pausedMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNull);
      expect(db.getTodayReadingMinutes(), equals(initialMinutes + 1));

      // 3. Background time elapses (e.g. 2 hours in background)
      // Since timer is null, no session runs while paused.

      // 4. Reader resumed -> restarts timer from now
      final resumedMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderResumed', {
          'bookId': bookId,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', resumedMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNotNull);

      // Simulate another 60 seconds of active reading
      ReadiumReaderService.activeSessionStartTime =
          DateTime.now().subtract(const Duration(seconds: 60));

      // 5. Reader closes -> flushes 60s and CLEARS timer (null)
      final closedMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderClosed', {
          'bookId': bookId,
          'locator': '{"href":"ch1.xhtml"}',
          'totalProgression': 0.15,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', closedMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNull);
      // Total reading time MUST be 2 minutes, NOT 2 hours + 2 minutes!
      expect(db.getTodayReadingMinutes(), equals(initialMinutes + 2));
    });

    test('onReaderError immediately cancels active session timer to avoid counting error screens', () async {
      ReadiumReaderService.activeSessionStartTime = DateTime.now();

      final errorMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderError', {
          'bookId': bookId,
          'requestId': 'req_err',
          'code': 'CORRUPT_EPUB',
          'message': 'Cannot parse container.xml',
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', errorMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNull);
    });

    test('Loading completion while backgrounded (isForegrounded: false) does NOT start session timer', () async {
      ReadiumReaderService.activeSessionStartTime = null;

      final readyMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderReady', {
          'bookId': bookId,
          'requestId': 'req_bg_race',
          'isForegrounded': false,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', readyMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNull);
      expect(ReadiumReaderService.isForegrounded, isFalse);

      // When reader is subsequently resumed by user returning to foreground:
      final resumeMsg = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onReaderResumed', {
          'bookId': bookId,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.hon.reader/readium_reader', resumeMsg, (ByteData? reply) {});

      expect(ReadiumReaderService.activeSessionStartTime, isNotNull);
      expect(ReadiumReaderService.isForegrounded, isTrue);
    });
  });
}
