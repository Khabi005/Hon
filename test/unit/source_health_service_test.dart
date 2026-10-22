import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/sources/source_health_service.dart';
import 'package:hon/core/sources/source_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourceHealthService', () {
    test('returns OK when searchSource succeeds', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_ok',
        'return { search = function() return {{title="Test Novel", link="test"}} end }',
      );

      final result = await SourceHealthService.testSource('test_ok');
      expect(result.state, SourceHealthState.ok);
      expect(result.label, 'OK');
      expect(result.isOk, isTrue);
    });

    test('detects Blocked by network policy and extracts blocked host', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_policy',
        'error("Source network policy: Domain \'gregariousfrog.com\' is not allowed")',
      );

      final result = await SourceHealthService.testSource('test_policy');
      expect(result.state, SourceHealthState.blockedByPolicy);
      expect(result.label, 'Blocked by network policy');
      expect(result.blockedHost, 'gregariousfrog.com');
      expect(result.details, contains('gregariousfrog.com'));
    });

    test('detects Cloudflare and Needs login', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_cf',
        'error("403 Forbidden: Cloudflare challenge required")',
      );

      final result = await SourceHealthService.testSource('test_cf');
      expect(result.state, SourceHealthState.needsLogin);
      expect(result.label, 'Needs login');
      expect(result.details, contains('Cloudflare'));
    });

    test('detects SSL / TLS certificate failure as Failing (reason)', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_ssl',
        'error("SSLHandshakeException: CertPathValidatorException: Trust anchor for certification path not found")',
      );

      final result = await SourceHealthService.testSource('test_ssl');
      expect(result.state, SourceHealthState.failing);
      expect(result.label, contains('Untrusted TLS certificate'));
    });

    test('produces comprehensive SourceDiagnosticsMatrix with truthful capability statuses', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_matrix',
        'return { search = function() return {{title="Test Novel", link="test"}} end }',
      );

      final matrix = await SourceHealthService.diagnoseSource('test_matrix');
      expect(matrix.sourceId, 'test_matrix');
      expect(matrix.health.isOk, isTrue);
      expect(matrix.capabilities.isNotEmpty, isTrue);

      final searchCap = matrix.capabilities.firstWhere((c) => c.name == 'Search');
      expect(searchCap.isSupported, isTrue);
      expect(searchCap.status, CapabilityStatus.working);

      final novelCap = matrix.capabilities.firstWhere((c) => c.name == 'Novel Parsing');
      expect(novelCap.isSupported, isTrue);
      expect(novelCap.status, CapabilityStatus.notTested);

      final passageCap = matrix.capabilities.firstWhere((c) => c.name == 'Passage Fetching');
      expect(passageCap.isSupported, isTrue);
      expect(passageCap.status, CapabilityStatus.notTested);
    });

    test('diagnoseSource marks Search as empty when query returns 0 results', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_matrix_empty',
        'return { search = function() return {} end }',
      );

      final matrix = await SourceHealthService.diagnoseSource('test_matrix_empty');
      final searchCap = matrix.capabilities.firstWhere((c) => c.name == 'Search');
      expect(searchCap.isSupported, isTrue);
      expect(searchCap.status, CapabilityStatus.empty);
      expect(searchCap.message, 'No results for test query');
    });

    test('diagnoseSource marks Search as failed when search execution throws', () async {
      // First probe (empty query '') passes, but search for query 'a' throws
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_matrix_fail',
        'return { search = function(data) if data[QUERY] == "a" then error("Simulated search syntax error") else return {{title="Init", link="init"}} end end }',
      );

      final matrix = await SourceHealthService.diagnoseSource('test_matrix_fail');
      final searchCap = matrix.capabilities.firstWhere((c) => c.name == 'Search');
      expect(searchCap.isSupported, isTrue);
      expect(searchCap.status, CapabilityStatus.failed);
      expect(searchCap.message, contains('Search failed'));
    });

    test('diagnoseSource evaluates Search independently when listing health probe fails', () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'test_matrix_listing_fail',
        'return { listings = {{name="Popular", id="pop"}}, search = function(data) if data[LISTING] ~= nil then error("Listing server down") else return {{title="Found Book", link="found"}} end end }',
      );

      final matrix = await SourceHealthService.diagnoseSource('test_matrix_listing_fail');
      expect(matrix.health.isOk, isFalse);

      final searchCap = matrix.capabilities.firstWhere((c) => c.name == 'Search');
      expect(searchCap.isSupported, isTrue);
      expect(searchCap.status, CapabilityStatus.working);
      expect(searchCap.message, contains('Operational'));

      final listingsCap = matrix.capabilities.firstWhere((c) => c.name == 'Catalog Listings');
      expect(listingsCap.status, CapabilityStatus.failed);
      expect(listingsCap.message, contains('Listing 0 failed'));
    });
  });
}
