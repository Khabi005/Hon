@Tags(['integration', 'live-network'])
library;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/sources/lua/shosetsu_lua_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShosetsuLuaEngine engine;
  late String gutenbergScript;
  bool isOnline = true;
  bool isLiveGated = false;

  setUpAll(() async {
    final liveEnv = Platform.environment['HON_LIVE_TESTS'];
    if (liveEnv != '1' && liveEnv != 'true') {
      isLiveGated = true;
      return;
    }

    // Disable Flutter test's default network interception for live integration tests
    HttpOverrides.global = null;

    final file = File('assets/sources/gutenberg.lua');
    expect(file.existsSync(), isTrue, reason: 'assets/sources/gutenberg.lua must exist');
    gutenbergScript = file.readAsStringSync();

    // Check live internet connectivity to gutenberg.org
    try {
      final lookup = await InternetAddress.lookup('www.gutenberg.org')
          .timeout(const Duration(seconds: 5));
      isOnline = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      isOnline = false;
    }
  });

  setUp(() {
    engine = ShosetsuLuaEngine.instance;
  });

  group('Live Network Integration — Upstream Project Gutenberg Extension', () {
    test('Live Search: queries live Project Gutenberg catalog for "pride"', () async {
      if (isLiveGated) {
        markTestSkipped('Skipping: HON_LIVE_TESTS environment variable is not set to 1 or true');
        return;
      }
      if (!isOnline) {
        markTestSkipped('Skipping: No live internet connectivity to www.gutenberg.org');
        return;
      }

      // Must succeed against live servers without catching or swallowing errors
      final results = await engine.search(gutenbergScript, 'pride', page: 0);
      expect(results, isNotEmpty);
      expect(results.length, greaterThanOrEqualTo(1));
      expect(
        results.any((n) => n.title.toLowerCase().contains('pride')),
        isTrue,
        reason: 'Live Gutenberg search results must contain novels matching query "pride"',
      );
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('Live Novel Details: parses Pride and Prejudice (/ebooks/1342) live from Gutenberg', () async {
      if (isLiveGated) {
        markTestSkipped('Skipping: HON_LIVE_TESTS environment variable is not set to 1 or true');
        return;
      }
      if (!isOnline) {
        markTestSkipped('Skipping: No live internet connectivity to www.gutenberg.org');
        return;
      }

      // Must succeed against live servers without catching or swallowing errors
      final details = await engine.parseNovel(gutenbergScript, '/ebooks/1342', loadChapters: true);
      expect(details.title, contains('Pride and Prejudice'));
      expect(details.author, contains('Austen'));
      expect(details.chapters, isNotEmpty);
      expect(details.chapters.first.url, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('Live Readable Passage: retrieves live Chapter 1 HTML from Gutenberg', () async {
      if (isLiveGated) {
        markTestSkipped('Skipping: HON_LIVE_TESTS environment variable is not set to 1 or true');
        return;
      }
      if (!isOnline) {
        markTestSkipped('Skipping: No live internet connectivity to www.gutenberg.org');
        return;
      }

      // Must succeed against live servers without catching or swallowing errors
      final passage = await engine.getPassage(
        gutenbergScript,
        '/cache/epub/1342/pg1342-images.html',
      );
      expect(passage, isNotEmpty);
      expect(passage.length, greaterThan(1000));
      expect(passage, contains('Chapter I.'));
      expect(
        passage,
        contains('truth universally acknowledged'),
      );
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
