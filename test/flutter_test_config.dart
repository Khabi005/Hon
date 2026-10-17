import 'dart:async';
import 'package:hon/core/database/app_database.dart';

/// Flutter test runner configuration hook.
/// Explicitly configures in-memory database fallback for headless unit tests
/// while ensuring production remains strictly protected against data loss.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppDatabase.allowMemoryFallbackForTesting = true;
  await testMain();
}
