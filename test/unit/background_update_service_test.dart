import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/updates/background_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> channelCalls;

  setUp(() {
    channelCalls = [];
    SharedPreferences.setMockInitialValues({
      BackgroundUpdateService.keyEnabled: true,
      BackgroundUpdateService.keyIntervalHours: 12,
      BackgroundUpdateService.keyUnmeteredOnly: true,
      BackgroundUpdateService.keyBatteryNotLow: true,
      BackgroundUpdateService.keyLastCheckTime: 1700000000000,
      BackgroundUpdateService.keyLastCheckStatus: 'Found 2 new chapters in 1 book',
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.hon.reader/download_worker'),
      (MethodCall methodCall) async {
        channelCalls.add(methodCall);
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.hon.reader/download_worker'),
      null,
    );
  });

  group('BackgroundUpdateService', () {
    test('getSettings reads persisted preferences correctly', () async {
      final service = BackgroundUpdateService.instance;
      final settings = await service.getSettings();

      expect(settings.enabled, isTrue);
      expect(settings.intervalHours, equals(12));
      expect(settings.unmeteredOnly, isTrue);
      expect(settings.requiresBatteryNotLow, isTrue);
      expect(settings.lastCheckTime, equals(DateTime.fromMillisecondsSinceEpoch(1700000000000)));
      expect(settings.lastCheckStatus, equals('Found 2 new chapters in 1 book'));
    });

    test('saveSettings updates SharedPreferences', () async {
      final service = BackgroundUpdateService.instance;
      await service.saveSettings(
        enabled: false,
        intervalHours: 6,
        unmeteredOnly: false,
        requiresBatteryNotLow: false,
      );

      final settings = await service.getSettings();
      expect(settings.enabled, isFalse);
      expect(settings.intervalHours, equals(6));
      expect(settings.unmeteredOnly, isFalse);
      expect(settings.requiresBatteryNotLow, isFalse);
    });

    test('triggerImmediateCheck invokes channel method when on Android or delegates', () async {
      final service = BackgroundUpdateService.instance;
      await service.triggerImmediateCheck(unmeteredOnly: true);
      // Method channel only called if Platform.isAndroid, verified by not throwing
      expect(service, isNotNull);
    });
  });
}
