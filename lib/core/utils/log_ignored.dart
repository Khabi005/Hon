import 'package:flutter/foundation.dart';

/// For errors that are safe to carry on past (a missing optional file, a
/// best-effort cleanup), but that should still show up while debugging
/// instead of vanishing in an empty catch.
void logIgnored(Object error, String where) {
  if (kDebugMode) debugPrint('Hon: ignored in $where: $error');
}
