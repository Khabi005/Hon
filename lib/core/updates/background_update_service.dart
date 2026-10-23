import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/log_ignored.dart';

class BackgroundUpdateSettings {
  final bool enabled;
  final int intervalHours; // 6, 12, 24
  final bool unmeteredOnly;
  final bool requiresBatteryNotLow;
  final bool requiresCharging;
  final DateTime? lastCheckTime;
  final String? lastCheckStatus;

  const BackgroundUpdateSettings({
    this.enabled = false,
    this.intervalHours = 24,
    this.unmeteredOnly = true,
    this.requiresBatteryNotLow = true,
    this.requiresCharging = false,
    this.lastCheckTime,
    this.lastCheckStatus,
  });

  BackgroundUpdateSettings copyWith({
    bool? enabled,
    int? intervalHours,
    bool? unmeteredOnly,
    bool? requiresBatteryNotLow,
    bool? requiresCharging,
    DateTime? lastCheckTime,
    String? lastCheckStatus,
  }) {
    return BackgroundUpdateSettings(
      enabled: enabled ?? this.enabled,
      intervalHours: intervalHours ?? this.intervalHours,
      unmeteredOnly: unmeteredOnly ?? this.unmeteredOnly,
      requiresBatteryNotLow:
          requiresBatteryNotLow ?? this.requiresBatteryNotLow,
      requiresCharging: requiresCharging ?? this.requiresCharging,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      lastCheckStatus: lastCheckStatus ?? this.lastCheckStatus,
    );
  }
}

class BackgroundUpdateService {
  static BackgroundUpdateService? _instance;
  static BackgroundUpdateService get instance =>
      _instance ??= BackgroundUpdateService._();
  BackgroundUpdateService._();

  static const MethodChannel _channel = MethodChannel(
    'com.hon.reader/download_worker',
  );

  static const String keyEnabled = 'hon_update_check_enabled';
  static const String keyIntervalHours = 'hon_update_check_interval_hours';
  static const String keyUnmeteredOnly = 'hon_update_check_unmetered_only';
  static const String keyBatteryNotLow = 'hon_update_check_battery_not_low';
  static const String keyCharging = 'hon_update_check_charging';
  static const String keyLastCheckTime = 'hon_last_update_check_time';
  static const String keyLastCheckStatus = 'hon_last_update_check_status';

  Future<BackgroundUpdateSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(keyEnabled) ?? false;
    final intervalHours = prefs.getInt(keyIntervalHours) ?? 24;
    final unmeteredOnly = prefs.getBool(keyUnmeteredOnly) ?? true;
    final batteryNotLow = prefs.getBool(keyBatteryNotLow) ?? true;
    final charging = prefs.getBool(keyCharging) ?? false;

    final lastTimeMillis = prefs.getInt(keyLastCheckTime);
    final lastTime = lastTimeMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastTimeMillis)
        : null;
    final lastStatus = prefs.getString(keyLastCheckStatus);

    return BackgroundUpdateSettings(
      enabled: enabled,
      intervalHours: intervalHours,
      unmeteredOnly: unmeteredOnly,
      requiresBatteryNotLow: batteryNotLow,
      requiresCharging: charging,
      lastCheckTime: lastTime,
      lastCheckStatus: lastStatus,
    );
  }

  Future<void> saveSettings({
    bool? enabled,
    int? intervalHours,
    bool? unmeteredOnly,
    bool? requiresBatteryNotLow,
    bool? requiresCharging,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getSettings();

    final newEnabled = enabled ?? current.enabled;
    final newInterval = intervalHours ?? current.intervalHours;
    final newUnmetered = unmeteredOnly ?? current.unmeteredOnly;
    final newBattery = requiresBatteryNotLow ?? current.requiresBatteryNotLow;
    final newCharging = requiresCharging ?? current.requiresCharging;

    await prefs.setBool(keyEnabled, newEnabled);
    await prefs.setInt(keyIntervalHours, newInterval);
    await prefs.setBool(keyUnmeteredOnly, newUnmetered);
    await prefs.setBool(keyBatteryNotLow, newBattery);
    await prefs.setBool(keyCharging, newCharging);

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('scheduleBackgroundUpdateChecks', {
          'enabled': newEnabled,
          'intervalHours': newInterval,
          'unmeteredOnly': newUnmetered,
          'batteryNotLow': newBattery,
          'charging': newCharging,
        });
      } catch (e) {
        logIgnored(e, 'background_update_service');
      }
    }
  }

  Future<void> triggerImmediateCheck({bool? unmeteredOnly}) async {
    if (Platform.isAndroid) {
      try {
        final current = await getSettings();
        await _channel.invokeMethod('triggerImmediateUpdateCheck', {
          'unmeteredOnly': unmeteredOnly ?? current.unmeteredOnly,
        });
      } catch (e) {
        logIgnored(e, 'background_update_service');
      }
    }
  }
}
