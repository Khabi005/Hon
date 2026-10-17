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

  setUpAll(() async {
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
      if (!isOnline) {
        // ignore: avoid_print
        print('SKIPPING: No internet connectivity to www.gutenberg.org');
        return;
      }

      try {
        final results = await engine.search(gutenbergScript, 'pride', page: 0);
        expect(results, isNotEmpty);
        // ignore: avoid_print
        print('Live search returned ${results.length} novels from Project Gutenberg.');
        expect(results.any((n) => n.title.toLowerCase().contains('pride')), isTrue);
      } on SourceNetworkException catch (e) {
        // ignore: avoid_print
        print('Live network request encountered: $e (skipping live assertion)');
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('Live Novel Details: parses Pride and Prejudice (/ebooks/1342) live from Gutenberg', () async {
      if (!isOnline) {
        // ignore: avoid_print
        print('SKIPPING: No internet connectivity to www.gutenberg.org');
        return;
      }

      try {
        final details = await engine.parseNovel(gutenbergScript, '/ebooks/1342', loadChapters: true);
        expect(details.title, isNotEmpty);
        expect(details.chapters, isNotEmpty);
        // ignore: avoid_print
        print('Live novel details loaded: "${details.title}" with ${details.chapters.length} chapters.');
      } on SourceNetworkException catch (e) {
        // ignore: avoid_print
        print('Live network request encountered: $e (skipping live assertion)');
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('Live Readable Passage: retrieves live Chapter 1 HTML from Gutenberg', () async {
      if (!isOnline) {
        // ignore: avoid_print
        print('SKIPPING: No internet connectivity to www.gutenberg.org');
        return;
      }

      try {
        final passage = await engine.getPassage(
          gutenbergScript,
          '/cache/epub/1342/pg1342-images.html',
        );
        expect(passage, isNotEmpty);
        // ignore: avoid_print
        print('Live passage retrieved: ${passage.length} characters.');
      } on SourceNetworkException catch (e) {
        // ignore: avoid_print
        print('Live network request encountered: $e (skipping live assertion)');
      }
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
