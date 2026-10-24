import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/log_ignored.dart';

/// Speaks text aloud. [speak] completes when the text has been spoken or
/// [stop] was called.
abstract class SpeechEngine {
  Future<void> speak(String text);
  Future<void> stop();

  /// [rate] is a multiple of normal speed: 1.0 is normal, 2.0 twice as fast.
  Future<void> setRate(double rate);
}

/// The platform text-to-speech voice.
class PlatformSpeechEngine implements SpeechEngine {
  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
    await _tts.awaitSpeakCompletion(true);
  }();

  @override
  Future<void> speak(String text) async {
    await _init();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> setRate(double rate) async {
    await _init();
    // flutter_tts treats 0.5 as normal speed on Android and iOS.
    await _tts.setSpeechRate((rate * 0.5).clamp(0.1, 1.0));
  }
}

/// Where the reader is, by chapter and paragraph (block).
typedef SpeechPosition = ({int chapter, int block});

/// Reads a web novel aloud paragraph by paragraph, like LNReader's TTS, and
/// carries on into the next chapter.
class ReaderTts extends ChangeNotifier {
  static const rates = [0.75, 1.0, 1.25, 1.5, 2.0];
  static const rateKey = 'hon_tts_rate';

  /// Android rejects utterances over 4000 characters.
  static const maxChunk = 3500;

  ReaderTts({
    required this.engine,
    required this.blocksOf,
    required this.chapterCount,
    required this.onPosition,
  }) {
    _loadRate();
  }

  final SpeechEngine engine;

  /// The paragraph texts of a chapter, loading it if needed; empty strings
  /// for images and dividers. Null if the chapter can't be loaded.
  final Future<List<String>?> Function(int chapter) blocksOf;
  final int Function() chapterCount;

  /// Called as each paragraph starts, so the reader can show it.
  final void Function(SpeechPosition position) onPosition;

  SpeechPosition? _position;
  SpeechPosition? get position => _position;

  bool _playing = false;
  bool get playing => _playing;

  /// True from the first [play] until [stop], paused or not.
  bool get active => _position != null;

  double rate = 1.0;
  int _generation = 0;

  Future<void> _loadRate() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(rateKey);
      if (saved != null && rates.contains(saved)) rate = saved;
      await engine.setRate(rate);
    } catch (e) {
      logIgnored(e, 'tts rate');
    }
  }

  /// Speaks from [chapter], paragraph [block], until stopped or the book
  /// ends.
  Future<void> play(int chapter, int block) async {
    final generation = ++_generation;
    await engine.stop();
    _playing = true;
    var current = (chapter: chapter, block: block);
    while (_generation == generation) {
      final blocks = await blocksOf(current.chapter);
      if (_generation != generation) return;
      if (blocks == null) break;
      if (current.block >= blocks.length) {
        if (current.chapter + 1 >= chapterCount()) break;
        current = (chapter: current.chapter + 1, block: 0);
        continue;
      }
      final text = blocks[current.block].trim();
      if (text.isNotEmpty) {
        _position = current;
        notifyListeners();
        onPosition(current);
        for (final chunk in splitForSpeech(text)) {
          await engine.speak(chunk);
          if (_generation != generation) return;
        }
      }
      current = (chapter: current.chapter, block: current.block + 1);
    }
    if (_generation == generation) {
      // Reached the end of the book.
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _generation++;
    _playing = false;
    notifyListeners();
    await engine.stop();
  }

  Future<void> resume() async {
    final at = _position;
    if (at != null) await play(at.chapter, at.block);
  }

  Future<void> stop() async {
    _generation++;
    _playing = false;
    _position = null;
    notifyListeners();
    await engine.stop();
  }

  /// Moves [delta] paragraphs, within the current chapter.
  Future<void> skip(int delta) async {
    final at = _position;
    if (at == null) return;
    final blocks = await blocksOf(at.chapter) ?? const <String>[];
    var block = at.block + delta;
    // Step over images and dividers.
    while (block >= 0 &&
        block < blocks.length &&
        blocks[block].trim().isEmpty) {
      block += delta.sign;
    }
    block = block.clamp(0, blocks.isEmpty ? 0 : blocks.length - 1);
    if (_playing) {
      await play(at.chapter, block);
    } else {
      _position = (chapter: at.chapter, block: block);
      notifyListeners();
      onPosition(_position!);
    }
  }

  /// Steps through [rates], restarting the current paragraph at the new
  /// speed.
  Future<void> cycleRate() async {
    rate = rates[(rates.indexOf(rate) + 1) % rates.length];
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setDouble(rateKey, rate);
    } catch (e) {
      logIgnored(e, 'tts rate');
    }
    await engine.setRate(rate);
    if (_playing) await resume();
  }

  @override
  void dispose() {
    _generation++;
    engine.stop().catchError((Object e) => logIgnored(e, 'tts stop'));
    super.dispose();
  }

  /// Splits [text] into pieces short enough to speak, at sentence ends
  /// where possible.
  @visibleForTesting
  static List<String> splitForSpeech(String text, {int max = maxChunk}) {
    if (text.length <= max) return [text];
    final chunks = <String>[];
    var rest = text;
    while (rest.length > max) {
      var cut = rest.lastIndexOf(RegExp(r'[.!?。！？]\s'), max);
      if (cut < max ~/ 3) cut = rest.lastIndexOf(' ', max);
      if (cut <= 0) cut = max - 1;
      chunks.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1);
    }
    if (rest.trim().isNotEmpty) chunks.add(rest.trim());
    return chunks;
  }
}
