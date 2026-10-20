import 'source_registry.dart';

enum SourceHealthState {
  ok,
  failing,
  needsLogin,
  blockedByPolicy,
}

class SourceHealthResult {
  final SourceHealthState state;
  final String label;
  final String? details;
  final String? blockedHost;
  final String? rawException;

  const SourceHealthResult({
    required this.state,
    required this.label,
    this.details,
    this.blockedHost,
    this.rawException,
  });

  bool get isOk => state == SourceHealthState.ok;
}

class SourceHealthService {
  static Future<SourceHealthResult> testSource(String sourceId) async {
    try {
      await SourceRegistry.instance.searchSource(sourceId, '', listing: 0);
      return const SourceHealthResult(
        state: SourceHealthState.ok,
        label: 'OK',
        details: 'Source is online and responding normally.',
      );
    } catch (e) {
      final raw = e.toString();
      final lower = raw.toLowerCase();

      if (lower.contains('source network policy') ||
          lower.contains('network policy') ||
          lower.contains('policy violation') ||
          lower.contains('domain not allowed') ||
          lower.contains('is not allowed')) {
        final hostMatch = RegExp(
          r"(?:domain|host|url|address)[\s:='`]+([a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})",
          caseSensitive: false,
        ).firstMatch(raw) ??
            RegExp(
              r"https?://([a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})",
              caseSensitive: false,
            ).firstMatch(raw) ??
            RegExp(
              r"'([a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})'",
              caseSensitive: false,
            ).firstMatch(raw);
        final host = hostMatch?.group(1);
        return SourceHealthResult(
          state: SourceHealthState.blockedByPolicy,
          label: 'Blocked by network policy',
          details: host != null
              ? 'Attempted to access undeclared host "$host".'
              : 'Attempted to access an undeclared domain.',
          blockedHost: host,
          rawException: raw,
        );
      }

      if (lower.contains('cloudflare') ||
          lower.contains('captcha') ||
          lower.contains('403 forbidden') ||
          lower.contains('needs login') ||
          lower.contains('unauthorized') ||
          lower.contains('sign in')) {
        return SourceHealthResult(
          state: SourceHealthState.needsLogin,
          label: 'Needs login',
          details: 'Protected by Cloudflare or requires account authentication.',
          rawException: raw,
        );
      }

      String reason = 'Unexpected error';
      if (lower.contains('sslhandshakeexception') ||
          lower.contains('certpathvalidatorexception') ||
          lower.contains('trust anchor') ||
          lower.contains('certificate')) {
        reason = 'Untrusted TLS certificate';
      } else if (lower.contains('sockettimeoutexception') ||
          lower.contains('timeout') ||
          lower.contains('timed out')) {
        reason = 'Connection timed out';
      } else if (lower.contains('429') || lower.contains('too many requests')) {
        reason = 'Rate limited (429)';
      } else if (lower.contains('404')) {
        reason = 'Endpoint not found (404)';
      } else if (lower.contains('500') || lower.contains('502') || lower.contains('503')) {
        reason = 'Server error (${lower.contains('502') ? '502' : lower.contains('503') ? '503' : '500'})';
      } else {
        final firstLine = raw.split('\n').first;
        final clean = firstLine.replaceAll(
          RegExp(r'^(Exception|PlatformException|SourceNetworkException):\s*'),
          '',
        );
        reason = clean.length > 40 ? '${clean.substring(0, 37)}...' : clean;
      }

      return SourceHealthResult(
        state: SourceHealthState.failing,
        label: 'Failing ($reason)',
        details: reason,
        rawException: raw,
      );
    }
  }
}
