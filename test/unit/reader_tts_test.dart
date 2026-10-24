import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hon/features/reader/presentation/reader_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what is spoken. With [hold] set, each utterance waits until
/// [finish] or [stop] is called.
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({this.hold = false});

  final bool hold;
  final spoken = <String>[];
  final rates = <double>[];
  Completer<void>? _current;

  void finish() => _current?.complete();

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    if (!hold) return Future.value();
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> stop() async {
    final current = _current;
    _current = null;
    if (current != null && !current.isCompleted) current.complete();
  }

  @override
  Future<void> setRate(double rate) async => rates.add(rate);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final book = {
    0: ['One a', '', 'One b'],
    1: ['Two a', 'Two b'],
  };

  ReaderTts make(FakeSpeechEngine engine, List<SpeechPosition> shown) =>
      ReaderTts(
        engine: engine,
        blocksOf: (chapter) async => book[chapter],
        chapterCount: () => book.length,
        onPosition: shown.add,
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads on into the next chapter and skips empty blocks', () async {
    final engine = FakeSpeechEngine();
    final shown = <SpeechPosition>[];
    final tts = make(engine, shown);
    await tts.play(0, 0);
    expect(engine.spoken, ['One a', 'One b', 'Two a', 'Two b']);
    expect(shown.last, (chapter: 1, block: 1));
    expect(tts.playing, isFalse);
    tts.dispose();
  });

  test('pause, skip and stop', () async {
    final engine = FakeSpeechEngine(hold: true);
    final shown = <SpeechPosition>[];
    final tts = make(engine, shown);
    unawaited(tts.play(0, 0));
    await pumpEventQueue();
    expect(engine.spoken, ['One a']);
    expect(tts.playing, isTrue);

    // Skipping forward steps over the empty divider block.
    unawaited(tts.skip(1));
    await pumpEventQueue();
    expect(engine.spoken.last, 'One b');
    expect(tts.position, (chapter: 0, block: 2));

    await tts.pause();
    expect(tts.playing, isFalse);
    expect(tts.active, isTrue);
    await tts.skip(-1);
    expect(tts.position, (chapter: 0, block: 0));
    expect(engine.spoken, hasLength(2), reason: 'paused skips stay quiet');

    unawaited(tts.resume());
    await pumpEventQueue();
    expect(engine.spoken.last, 'One a');

    await tts.stop();
    expect(tts.active, isFalse);
    engine.finish();
    await pumpEventQueue();
    expect(engine.spoken, hasLength(3), reason: 'nothing after stop');
    tts.dispose();
  });

  test('cycles and remembers the speed', () async {
    final engine = FakeSpeechEngine();
    final tts = make(engine, []);
    await pumpEventQueue();
    await tts.cycleRate();
    expect(tts.rate, 1.25);
    expect(engine.rates.last, 1.25);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(ReaderTts.rateKey), 1.25);
    tts.dispose();

    final again = FakeSpeechEngine();
    final restored = make(again, []);
    await pumpEventQueue();
    expect(restored.rate, 1.25);
    restored.dispose();
  });

  test('splits long paragraphs at sentence ends', () {
    final text = List.filled(30, 'This is a sentence.').join(' ');
    final chunks = ReaderTts.splitForSpeech(text, max: 100);
    expect(chunks.every((c) => c.length <= 100), isTrue);
    expect(chunks.every((c) => c.endsWith('.')), isTrue);
    expect(chunks.join(' '), text);
    expect(ReaderTts.splitForSpeech('Short.'), ['Short.']);
  });
}
