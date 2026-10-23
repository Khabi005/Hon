import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/log_ignored.dart';

/// Reader input settings that are not part of the reading appearance.
class ReaderInputPreferences {
  static const volumeKeysKey = 'hon_reader_volume_keys';
  static const autoScrollSpeedKey = 'hon_reader_auto_scroll_speed';

  static Future<bool> volumeKeys() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(volumeKeysKey) ??
          false;
    } catch (e) {
      logIgnored(e, 'volume key preference');
      return false;
    }
  }

  static Future<void> setVolumeKeys(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(volumeKeysKey, value);
}

/// Scrolls the reader at a steady speed, like LNReader's auto-scroll. A
/// finger on the screen holds it; lifting the finger carries on.
class ReaderAutoScroller {
  static const minSpeed = 10.0;
  static const maxSpeed = 200.0;
  static const speedStep = 10.0;

  ReaderAutoScroller({
    required TickerProvider vsync,
    required this.controller,
    required this.onChanged,
  }) {
    _ticker = vsync.createTicker(_tick);
    _loadSpeed();
  }

  final ScrollController controller;

  /// Called when running or speed changes, so the reader can rebuild.
  final VoidCallback onChanged;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Duration? _stuckSince;
  bool _held = false;

  /// Logical pixels per second.
  double speed = 40;

  bool get running => _ticker.isActive;

  Future<void> _loadSpeed() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(
        ReaderInputPreferences.autoScrollSpeedKey,
      );
      if (saved != null) speed = saved.clamp(minSpeed, maxSpeed);
    } catch (e) {
      logIgnored(e, 'auto-scroll speed');
    }
  }

  void start() {
    if (running) return;
    _last = Duration.zero;
    _stuckSince = null;
    _ticker.start();
    onChanged();
  }

  void stop() {
    if (!running) return;
    _ticker.stop();
    onChanged();
  }

  void toggle() => running ? stop() : start();

  /// Pauses while a finger is down, so reading back a line doesn't fight it.
  void hold(bool held) => _held = held;

  void changeSpeed(double delta) {
    speed = (speed + delta).clamp(minSpeed, maxSpeed);
    onChanged();
    SharedPreferences.getInstance()
        .then(
          (prefs) =>
              prefs.setDouble(ReaderInputPreferences.autoScrollSpeedKey, speed),
        )
        .catchError((Object e) {
          logIgnored(e, 'auto-scroll speed');
          return false;
        });
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_held || !controller.hasClients) return;
    final position = controller.position;
    final target = position.pixels + speed * seconds;
    if (target < position.maxScrollExtent) {
      _stuckSince = null;
      controller.jumpTo(target);
      return;
    }
    controller.jumpTo(position.maxScrollExtent);
    // The next chapter is appended near the end; stop once nothing more
    // arrives for a couple of seconds.
    _stuckSince ??= elapsed;
    if (elapsed - _stuckSince! > const Duration(seconds: 2)) stop();
  }

  void dispose() => _ticker.dispose();
}
