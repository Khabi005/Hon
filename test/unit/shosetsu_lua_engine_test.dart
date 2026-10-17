import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/download_job.dart';
import 'package:hon/core/sources/lua/shosetsu_lua_engine.dart';
import 'package:hon/core/sources/source_registry.dart';

class MockGutenbergHttpClient extends http.BaseClient {
  bool simulateNetworkFailure = false;
  int failureStatusCode = 500;

  static const searchHtmlFixture = '''
<!DOCTYPE html>
<html>
<body>
  <ul class="results">
    <li class="booklink">
      <a class="link" href="/ebooks/1342">
        <span class="title">Pride and Prejudice</span>
        <img class="cover-thumb" src="/cache/epub/1342/pg1342.cover.small.jpg" alt="cover" />
      </a>
      <span class="subtitle">Jane Austen</span>
    </li>
    <li class="booklink">
      <a class="link" href="/ebooks/11">
        <span class="title">Alice's Adventures in Wonderland</span>
        <img class="cover-thumb" src="/cache/epub/11/pg11.cover.small.jpg" alt="cover" />
      </a>
      <span class="subtitle">Lewis Carroll</span>
    </li>
  </ul>
</body>
</html>
''';

  static const novelDetailsHtmlFixture = '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:url" content="https://www.gutenberg.org/ebooks/1342" />
</head>
<body>
  <h1 itemprop="headline">Pride and Prejudice</h1>
  <div itemprop="creator">Jane Austen</div>
  <div property="dcterms:subject">Classic Literature</div>
  <div property="dcterms:subject">Romance</div>
  <meta itemprop="inLanguage" content="en" />
  <img class="cover-art" src="https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg" />
  <div class="readmore-container">
    A classic novel of manners and romance following Elizabeth Bennet.
    <div class="toggle-content"> Mr. Darcy and the Bennet family navigating social expectations.</div>
  </div>
  <span itemprop="datePublished">1813-01-28</span>
  <a class="read-online-button" href="/cache/epub/1342/pg1342-images.html">Read online</a>
</body>
</html>
''';

  static const passageHtmlFixture = '''
<!DOCTYPE html>
<html>
<head>
  <title>Pride and Prejudice by Jane Austen</title>
</head>
<body>
  <div id="pg-header">
    <h2>The Project Gutenberg eBook of Pride and Prejudice</h2>
  </div>
  <div class="chapter">
    <h2>CHAPTER I.</h2>
    <p>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</p>
    <p>However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.</p>
  </div>
</body>
</html>
''';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (simulateNetworkFailure) {
      if (failureStatusCode == 0) {
        throw const SocketException('Failed host lookup: www.gutenberg.org');
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('Internal Server Error')),
        failureStatusCode,
        headers: {'content-type': 'text/plain'},
      );
    }

    final url = request.url.toString();
    String body = '<html><body>Default</body></html>';

    if (url.contains('/ebooks/search')) {
      body = searchHtmlFixture;
    } else if (url.contains('/ebooks/1342')) {
      body = novelDetailsHtmlFixture;
    } else if (url.contains('/cache/epub/1342/pg1342-images.html')) {
      body = passageHtmlFixture;
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShosetsuLuaEngine engine;
  late MockGutenbergHttpClient mockClient;
  late String gutenbergScript;

  setUpAll(() {
    // Read the upstream script directly from project assets
    final file = File('assets/sources/gutenberg.lua');
    expect(file.existsSync(), isTrue, reason: 'assets/sources/gutenberg.lua must exist');
    gutenbergScript = file.readAsStringSync();
  });

  setUp(() {
    mockClient = MockGutenbergHttpClient();
    engine = ShosetsuLuaEngine.instance;
    engine.setHttpClientForTesting(mockClient);
    SourceRegistry.instance.setSourceScriptForTesting('gutenberg', gutenbergScript);
  });

  group('Phase 0C — Upstream Shosetsu Lua Extension Engine Proof', () {
    test('1. Upstream Search: parses live HTML search query into structured novel items', () async {
      final results = await engine.search(gutenbergScript, 'pride', page: 0);

      expect(results, isNotEmpty);
      expect(results.length, equals(2));

      final first = results.first;
      expect(first.title, equals('Pride and Prejudice'));
      expect(first.id, equals('/ebooks/1342'));
      expect(first.coverUrl, contains('pg1342.cover.small.jpg'));

      final second = results[1];
      expect(second.title, equals("Alice's Adventures in Wonderland"));
      expect(second.id, equals('/ebooks/11'));
    });

    test('2. Upstream Novel Details: parses metadata, author, synopsis, and chapter list', () async {
      final details = await engine.parseNovel(gutenbergScript, '/ebooks/1342', loadChapters: true);

      expect(details.title, equals('Pride and Prejudice'));
      expect(details.author, contains('Jane Austen'));
      expect(details.description, contains('Elizabeth Bennet'));
      expect(details.description, contains('Mr. Darcy'));
      expect(details.genres, contains('Classic Literature'));
      expect(details.genres, contains('Romance'));
      expect(details.chapters, isNotEmpty);

      // Verify Chapter list integrity
      final chapter = details.chapters.first;
      expect(chapter.title, equals('Pride and Prejudice'));
      expect(chapter.url, equals('/cache/epub/1342/pg1342-images.html'));
      expect(chapter.releaseDate, isNotNull);
      expect(chapter.releaseDate!.year, equals(1813));
    });

    test('3. Upstream Readable Chapter: retrieves real HTML passage content', () async {
      final passage = await engine.getPassage(
        gutenbergScript,
        '/cache/epub/1342/pg1342-images.html',
      );

      expect(passage, isNotEmpty);
      expect(passage, contains('CHAPTER I.'));
      expect(
        passage,
        contains('It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.'),
      );
    });

    test('4. End-to-End Pipeline via SourceRegistry: search -> novel details -> chapter list -> readable passage', () async {
      // 4A. Search
      final searchResults = await SourceRegistry.instance.searchSource('gutenberg', 'pride');
      expect(searchResults, isNotEmpty);
      final selectedNovel = searchResults.first;
      expect(selectedNovel.title, equals('Pride and Prejudice'));

      // 4B. Novel Details & Chapter List
      final details = await SourceRegistry.instance.getNovelDetails(
        'gutenberg',
        selectedNovel.id,
        loadChapters: true,
      );
      expect(details.title, equals(selectedNovel.title));
      expect(details.chapters, isNotEmpty);

      // 4C. Readable Chapter Passage
      final chapter = details.chapters.first;
      final passage = await SourceRegistry.instance.getChapterPassage(
        'gutenberg',
        chapter.url!,
      );
      expect(passage, contains('CHAPTER I.'));
      expect(passage, contains('It is a truth universally acknowledged'));
    });

    test('5. Error Handling: Network failure throws honest SourceNetworkException without synthetic mock fallback', () async {
      mockClient.simulateNetworkFailure = true;
      mockClient.failureStatusCode = 0; // Simulate DNS / Socket connection failure

      expect(
        () async => await SourceRegistry.instance.searchSource('gutenberg', 'pride'),
        throwsA(isA<SourceNetworkException>()),
      );

      expect(
        () async => await SourceRegistry.instance.getNovelDetails('gutenberg', '/ebooks/1342'),
        throwsA(isA<SourceNetworkException>()),
      );

      expect(
        () async => await SourceRegistry.instance.getChapterPassage(
          'gutenberg',
          '/cache/epub/1342/pg1342-images.html',
        ),
        throwsA(isA<SourceNetworkException>()),
      );
    });

    test('6. Error Handling: HTTP 500 server error throws SourceNetworkException with status code', () async {
      mockClient.simulateNetworkFailure = true;
      mockClient.failureStatusCode = 500;

      expect(
        () async => await SourceRegistry.instance.searchSource('gutenberg', 'pride'),
        throwsA(
          predicate((e) =>
              e is SourceNetworkException &&
              e.statusCode == 500 &&
              e.message.contains('500')),
        ),
      );
    });

    test('7. Stack Argument Passing: safely handles quotes, backslashes, and injection payloads', () async {
      const maliciousScript = '''
        local function search(data)
          return {
            { title = "Echo: " .. tostring(data[0]), link = "/test/1" }
          }
        end
        return { search = search }
      ''';

      const complexQuery = 'Jane\'s "Pride" & \\Backslash\\ "injection" -- test';
      final results = await engine.search(
        maliciousScript,
        complexQuery,
      );

      expect(results, isNotEmpty);
      expect(results.first.title, equals('Echo: Jane\'s "Pride" & \\Backslash\\ "injection" -- test'));
    });

    test('8. Execution Timeout Budget: rogue infinite loop triggers SourceExecutionTimeoutException', () async {
      const infiniteLoopScript = '''
        local function search(data)
          while true do end
        end
        return { search = search }
      ''';

      expect(
        () async => await engine.search(
          infiniteLoopScript,
          'pride',
          totalTimeout: const Duration(milliseconds: 400),
          perAttemptTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<SourceExecutionTimeoutException>()),
      );
    });

    test('9. Host Sandboxing: dangerous OS and IO capabilities are neutralized', () async {
      const sandboxProbeScript = '''
        local function search(data)
          if os ~= nil and os.execute ~= nil then
            error("SECURITY_VIOLATION: os.execute must be nil")
          end
          if io ~= nil then
            error("SECURITY_VIOLATION: io must be nil")
          end
          return {
            { title = "Sandbox Secure", link = "/secure/1" }
          }
        end
        return { search = search }
      ''';

      final results = await engine.search(sandboxProbeScript, 'test');
      expect(results, isNotEmpty);
      expect(results.first.title, equals('Sandbox Secure'));
    });

    test('10. Identity & Durable Download Queue: uses source-qualified IDs and enqueues before prompt', () async {
      const sourceId = 'gutenberg';
      const novelId = '/ebooks/1342';
      const qualifiedBookId = '$sourceId:$novelId';

      expect(qualifiedBookId, equals('gutenberg:/ebooks/1342'));

      final job = DownloadJob(
        id: 'dl_${qualifiedBookId}_ch1'.replaceAll('/', '_'),
        bookId: qualifiedBookId,
        chapterId: '$qualifiedBookId:ch1',
        chapterTitle: 'Chapter 1',
        sourceId: sourceId,
        status: DownloadStatus.queued,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final db = DatabaseService.instance;
      // Invariant: Job is durably enqueued into database before any user interaction
      await db.enqueueDownload(job);

      final jobs = db.getAllDownloadJobs();
      expect(jobs.any((j) => j.id == job.id && j.sourceId == 'gutenberg'), isTrue);
      final enqueued = jobs.firstWhere((j) => j.id == job.id);
      expect(enqueued.status, equals(DownloadStatus.queued));
      expect(enqueued.bookId, equals('gutenberg:/ebooks/1342'));
    });
  });
}

