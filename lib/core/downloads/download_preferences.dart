import 'package:shared_preferences/shared_preferences.dart';

/// Download automation switches. The keys are also read by the Android
/// update worker (as `flutter.<key>` in FlutterSharedPreferences), so keep
/// them stable.
class DownloadPreferences {
  DownloadPreferences._();

  static const autoDownloadNewKey = 'hon_auto_download_new';
  static const deleteAfterReadingKey = 'hon_delete_after_reading';

  /// Queue chapters that an update check finds.
  static Future<bool> autoDownloadNew() async =>
      (await SharedPreferences.getInstance()).getBool(autoDownloadNewKey) ??
      false;

  static Future<void> setAutoDownloadNew(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        autoDownloadNewKey,
        value,
      );

  /// Remove a chapter's offline file once the reader moves on to the next.
  static Future<bool> deleteAfterReading() async =>
      (await SharedPreferences.getInstance()).getBool(deleteAfterReadingKey) ??
      false;

  static Future<void> setDeleteAfterReading(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        deleteAfterReadingKey,
        value,
      );
}
