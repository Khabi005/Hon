import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SourcePreferences {
  static final Map<String, String> migrationErrors = {};
  static const channel = MethodChannel('com.hon.reader/shosetsu_native');
  static Future<Map<String, dynamic>> read(
    String source, {
    bool filters = false,
  }) async {
    if (!filters && Platform.isAndroid) {
      final value = await channel.invokeMapMethod<String, dynamic>('getSourcePreferences', {'sourceId': source});
      return value ?? <String, dynamic>{};
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      return Map<String, dynamic>.from(
        jsonDecode(
              prefs.getString(
                    'hon_source_${filters ? 'filters' : 'settings'}_$source',
                  ) ??
                  '{}',
            )
            as Map,
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(
    String source,
    Map<String, dynamic> values, {
    bool filters = false,
    List<String> secretKeys = const [],
  }) async {
    if (!filters && Platform.isAndroid) {
      await channel.invokeMethod('setSourcePreferences', {
        'sourceId': source,
        'settings': values,
      });
    }
    final prefs = await SharedPreferences.getInstance();
    if (!filters) {
      await prefs.setStringList('hon_source_secret_keys_$source', secretKeys);
    }
    await prefs.setString(
      'hon_source_${filters ? 'filters' : 'settings'}_$source',
      jsonEncode(!filters && Platform.isAndroid
          ? Map.fromEntries(values.entries.where((entry) => !secretKeys.contains(entry.key)))
          : values),
    );
  }

  static Future<void> syncNative() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('hon_source_settings_'),
    )) {
      final source = key.substring('hon_source_settings_'.length);
      if (RegExp(r'^(ext_[0-9a-f]{64}|gutenberg)$').hasMatch(source)) {
        try {
        final values = Map<String, dynamic>.from(jsonDecode(prefs.getString(key) ?? '{}') as Map);
        await channel.invokeMethod('importSourcePreferences', {
          'sourceId': source,
          'settings': values,
        });
        final secrets = prefs.getStringList('hon_source_secret_keys_$source') ?? const <String>[];
        for (final secret in secrets) { values.remove(secret); }
        await prefs.setString(key, jsonEncode(values));
        migrationErrors.remove(source);
        } catch (error) {
          migrationErrors[source] = error.toString();
          debugPrint('Could not migrate source preferences for $source: $error');
        }
      }
    }
  }

  static Future<void> openWebsite(String source, String url) =>
      channel.invokeMethod<void>('openSourceWebsite', {
        'sourceId': source,
        'url': url,
      });
}
