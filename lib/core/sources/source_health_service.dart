import 'source_registry.dart';

enum SourceHealthState {
  ok,
  failing,
  needsLogin,
  blockedByPolicy,
}

enum CapabilityStatus {
  notTested,
  working,
  empty,
  failed,
  unsupported,
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

  /// Evaluates full source capabilities and produces a diagnostic matrix.
  static Future<SourceDiagnosticsMatrix> diagnoseSource(String sourceId) async {
    final health = await testSource(sourceId);
    bool supportsSearch = false;
    bool supportsListings = false;
    final listings = <String>[];
    final capabilities = <SourceDiagnosticsCapability>[];

    try {
      final info = await SourceRegistry.instance.getCatalogInfo(sourceId);
      supportsSearch = info.hasSearch;
      supportsListings = info.listings.isNotEmpty;
      for (final l in info.listings) {
        listings.add(l.name);
      }
    } catch (_) {}

    CapabilityStatus searchStatus;
    String searchMessage;
    if (!supportsSearch) {
      searchStatus = CapabilityStatus.unsupported;
      searchMessage = 'Not supported by source';
    } else {
      try {
        final searchResults = await SourceRegistry.instance.searchSource(sourceId, 'a', listing: null);
        if (searchResults.isNotEmpty) {
          searchStatus = CapabilityStatus.working;
          searchMessage = 'Operational (${searchResults.length} found)';
        } else {
          searchStatus = CapabilityStatus.empty;
          searchMessage = 'No results for test query';
        }
      } catch (e) {
        final msg = e.toString().split('\n').first.replaceAll(RegExp(r'^(Exception|PlatformException):\s*'), '');
        searchStatus = CapabilityStatus.failed;
        searchMessage = 'Search failed: $msg';
      }
    }

    capabilities.add(SourceDiagnosticsCapability(
      name: 'Search',
      isSupported: supportsSearch,
      status: searchStatus,
      message: searchMessage,
    ));

    CapabilityStatus listingsStatus;
    String listingsMessage;
    if (!supportsListings) {
      listingsStatus = CapabilityStatus.unsupported;
      listingsMessage = 'No listings supported';
    } else if (listings.isEmpty) {
      listingsStatus = CapabilityStatus.empty;
      listingsMessage = 'No listings configured';
    } else if (!health.isOk) {
      listingsStatus = CapabilityStatus.failed;
      listingsMessage = 'Listing 0 failed: ${health.label}';
    } else {
      listingsStatus = CapabilityStatus.working;
      listingsMessage = '${listings.length} listings available';
    }

    capabilities.add(SourceDiagnosticsCapability(
      name: 'Catalog Listings',
      isSupported: supportsListings,
      status: listingsStatus,
      message: listingsMessage,
    ));

    // Finding 10: truthfully report Novel Parsing and Passage Fetching as notTested
    // unless explicitly verified with real novel/passage probes.
    capabilities.add(const SourceDiagnosticsCapability(
      name: 'Novel Parsing',
      isSupported: true,
      status: CapabilityStatus.notTested,
      message: 'Not tested (requires novel inspection)',
    ));

    capabilities.add(const SourceDiagnosticsCapability(
      name: 'Passage Fetching',
      isSupported: true,
      status: CapabilityStatus.notTested,
      message: 'Not tested (requires passage inspection)',
    ));

    return SourceDiagnosticsMatrix(
      sourceId: sourceId,
      health: health,
      supportsSearch: supportsSearch,
      supportsListings: supportsListings,
      availableListings: listings,
      capabilities: capabilities,
    );
  }
}

class SourceDiagnosticsCapability {
  final String name;
  final bool isSupported;
  final CapabilityStatus status;
  final String? message;

  const SourceDiagnosticsCapability({
    required this.name,
    required this.isSupported,
    required this.status,
    this.message,
  });

  bool get isWorking => status == CapabilityStatus.working;
}

class SourceDiagnosticsMatrix {
  final String sourceId;
  final SourceHealthResult health;
  final bool supportsSearch;
  final bool supportsListings;
  final List<String> availableListings;
  final List<SourceDiagnosticsCapability> capabilities;

  const SourceDiagnosticsMatrix({
    required this.sourceId,
    required this.health,
    this.supportsSearch = false,
    this.supportsListings = false,
    this.availableListings = const [],
    this.capabilities = const [],
  });
}
