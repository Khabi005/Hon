import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/sources/extension_repository_service.dart';
import 'package:hon/core/sources/installed_extension_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('hon-extension-test-');
    StorageService.instance.setBaseDirForTesting(directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  const script =
      'return { search = function() return {} end, parseNovel = function() return {} end, getPassage = function() return "chapter" end }';
  final repository = ExtensionRepository(
    id: 'sample-repository',
    name: 'Sample',
    url: 'https://example.org/repo/',
    refreshedAt: DateTime(2026),
    scripts: const [],
  );

  RepositoryScript entry({
    String? checksum,
    List<String> dependencies = const [],
  }) => RepositoryScript(
    id: 'sample',
    name: 'Sample Script',
    language: 'eng',
    fileName: 'sample',
    version: '1.0',
    libraryVersion: '',
    checksum: checksum,
    dependencies: dependencies,
  );

  test('installs, persists, disables, enables and removes a script', () async {
    Uri? requested;
    final service = InstalledExtensionService(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(script, 200, request: request);
      }),
    );
    final installed = await service.install(
      repository,
      entry(checksum: md5.convert(utf8.encode(script)).toString()),
    );
    expect(requested.toString(), 'https://example.org/repo/src/eng/sample.lua');
    expect(await service.loadScript(installed.sourceId), script);
    await service.setEnabled(installed.sourceId, false);
    expect(File(installed.scriptPath).existsSync(), isFalse);
    await expectLater(
      service.loadScript(installed.sourceId),
      throwsFormatException,
    );

    final restored = InstalledExtensionService();
    await restored.init();
    expect(restored.find(installed.sourceId)?.enabled, isFalse);
    await restored.setEnabled(installed.sourceId, true);
    expect(await restored.loadScript(installed.sourceId), script);
    await restored.uninstall(installed.sourceId);
    expect(File(installed.scriptPath).existsSync(), isFalse);
    expect(restored.find(installed.sourceId), isNull);
  });

  test('accepts SHA-256 hashes from the current Universe index', () async {
    final service = InstalledExtensionService(
      client: MockClient(
        (request) async => http.Response(script, 200, request: request),
      ),
    );
    final installed = await service.install(
      repository,
      entry(checksum: sha256.convert(utf8.encode(script)).toString()),
    );
    expect(await service.loadScript(installed.sourceId), script);
  });

  test('rejects bad checksum and missing library dependencies', () async {
    final service = InstalledExtensionService(
      client: MockClient(
        (request) async => http.Response(script, 200, request: request),
      ),
    );
    await expectLater(
      service.install(repository, entry(checksum: 'bad')),
      throwsFormatException,
    );
    await expectLater(
      service.install(repository, entry(dependencies: ['helper'])),
      throwsFormatException,
    );
    expect(service.installed, isEmpty);
  });
  test('resolves nested helpers within the repository lib directory', () async {
    final requested = <String>[];
    final service = InstalledExtensionService(
      client: MockClient((request) async {
        requested.add(request.url.path);
        final body = switch (request.url.path) {
          '/repo/lib/XMLLua.lua' => "return Require('XMLLua/Parser')",
          '/repo/lib/XMLLua/Parser.lua' => 'return {parse = function() end}',
          _ => "local xml = Require('XMLLua')\n$script",
        };
        return http.Response(body, 200, request: request);
      }),
    );
    final repo = ExtensionRepository(
      id: repository.id,
      name: repository.name,
      url: repository.url,
      refreshedAt: repository.refreshedAt,
      scripts: const [],
      libraries: const {'XMLLua': '1.0.0'},
    );
    final installed = await service.install(repo, entry());
    final bundle = await service.loadScript(installed.sourceId);
    expect(requested, contains('/repo/lib/XMLLua/Parser.lua'));
    expect(bundle, contains('__modules["XMLLua/Parser"]'));
  });
  test(
    'bundles declared shared libraries atomically and preserves old install on failure',
    () async {
      const dependent =
          "-- {\"libVer\":\"1.0.0\",\"dep\":[\"helper>=1.0.0\"]}\nlocal h = Require('helper')\nreturn h";
      var fail = false;
      final service = InstalledExtensionService(
        client: MockClient((request) async {
          if (fail) return http.Response('failed', 503, request: request);
          return http.Response(
            request.url.path.endsWith('/helper.lua') ? script : dependent,
            200,
            request: request,
          );
        }),
      );
      final repo = ExtensionRepository(
        id: repository.id,
        name: repository.name,
        url: repository.url,
        refreshedAt: repository.refreshedAt,
        scripts: const [],
        libraries: const {'helper': '1.0.0'},
      );
      final installed = await service.install(repo, entry());
      final bundle = await service.loadScript(installed.sourceId);
      expect(bundle, contains('__modules["helper"]'));
      expect(bundle, contains(script));
      fail = true;
      await expectLater(service.install(repo, entry()), throwsFormatException);
      expect(await service.loadScript(installed.sourceId), bundle);
    },
  );

  test(
    'install from repository sets allowedHosts only to declared bootstrap hosts without repo host',
    () async {
      const scriptWithBase =
          'local baseURL = "https://source.example.com"\nreturn { search = function() return {} end }';
      final service = InstalledExtensionService(
        client: MockClient(
          (request) async =>
              http.Response(scriptWithBase, 200, request: request),
        ),
      );
      final repo = ExtensionRepository(
        id: 'external-repo',
        name: 'External Repo',
        url: 'https://repo.unrelated-domain.org/shosetsu/',
        refreshedAt: DateTime(2026),
        scripts: const [],
      );
      const scriptEntry = RepositoryScript(
        id: 'secure-source',
        name: 'Secure Source',
        language: 'en',
        fileName: 'secure_source',
        version: '1.0.0',
        libraryVersion: '',
        allowedHosts: ['api.source.example.com'],
      );

      final installed = await service.install(repo, scriptEntry);

      // Must include baseURL host and declared allowedHosts
      expect(installed.allowedHosts, contains('source.example.com'));
      expect(installed.allowedHosts, contains('api.source.example.com'));
      // Must NOT silently grant the repository domain
      expect(
        installed.allowedHosts,
        isNot(contains('repo.unrelated-domain.org')),
      );
    },
  );

  test(
    'update preserves user-added allowed hosts and disabled state',
    () async {
      const scriptV1 =
          'local baseURL = "https://source.example.com"\nreturn { search = function() return {} end }';
      const scriptV2 =
          'local baseURL = "https://source.example.com"\nreturn { search = function() return {1} end }';
      var version = '1.0.0';
      final service = InstalledExtensionService(
        client: MockClient(
          (request) async => http.Response(
            version == '1.0.0' ? scriptV1 : scriptV2,
            200,
            request: request,
          ),
        ),
      );
      final repo = ExtensionRepository(
        id: 'repo-1',
        name: 'Repo 1',
        url: 'https://repo1.org/',
        refreshedAt: DateTime(2026),
        scripts: const [],
      );
      const scriptEntryV1 = RepositoryScript(
        id: 'source-1',
        name: 'Source 1',
        language: 'en',
        fileName: 'source_1',
        version: '1.0.0',
        libraryVersion: '',
        allowedHosts: ['api.source.example.com'],
      );

      final installed = await service.install(repo, scriptEntryV1);
      expect(installed.enabled, isTrue);

      // User adds a custom host and disables the source
      await service.updateAllowedHosts(installed.sourceId, [
        ...installed.allowedHosts,
        'user-custom-cdn.net',
      ]);
      await service.setEnabled(installed.sourceId, false);

      expect(service.find(installed.sourceId)?.enabled, isFalse);
      expect(
        service.find(installed.sourceId)?.allowedHosts,
        contains('user-custom-cdn.net'),
      );

      // Now update the extension to version 2.0.0
      version = '2.0.0';
      const scriptEntryV2 = RepositoryScript(
        id: 'source-1',
        name: 'Source 1',
        language: 'en',
        fileName: 'source_1',
        version: '2.0.0',
        libraryVersion: '',
        allowedHosts: [
          'api.source.example.com',
          'v2-api.source.example.com',
        ],
      );


      final updated = await service.install(repo, scriptEntryV2);

      // User-added host permission MUST be preserved
      expect(updated.allowedHosts, contains('user-custom-cdn.net'));
      expect(updated.allowedHosts, contains('v2-api.source.example.com'));
      // Disabled state MUST be preserved
      expect(updated.enabled, isFalse);
      expect(service.find(installed.sourceId)?.enabled, isFalse);
    },
  );

  test(
    'uninstalled sources are not resurrected on catalog refresh unless explicitly reinstalled',
    () async {
      final service = InstalledExtensionService();
      await service.init();

      // Seed a bundled source
      final bundledSource = {
        'sourceId':
            'ext_1111111111111111111111111111111111111111111111111111111111111111',
        'repositoryId': 'repo_1',
        'repositoryUrl': 'https://repo.org/',
        'scriptId': 's1',
        'name': 'Source One',
        'language': 'en',
        'version': '1.0.0',
        'asset': 'assets/sources/bundled/s1.lua',
        'sha256': sha256.convert(utf8.encode(script)).toString(),
        'allowedHosts': ['source1.org'],
      };

      await service.seedBundled(
        [bundledSource],
        (asset) async => script,
      );
      final id = bundledSource['sourceId'] as String;
      expect(service.find(id), isNotNull);

      // Deliberately uninstall the source
      await service.uninstall(id);
      expect(service.find(id), isNull);

      // Re-running catalog seed (e.g. app update / hash refresh) must NOT resurrect it
      await service.seedBundled(
        [bundledSource],
        (asset) async => script,
      );
      expect(service.find(id), isNull, reason: 'Must not resurrect deliberately uninstalled source');

      // Unmarking removed (explicit reinstall by user) allows it to be reinstalled
      await service.unmarkRemoved(id);
      await service.seedBundled(
        [bundledSource],
        (asset) async => script,
      );
      expect(service.find(id), isNotNull, reason: 'Explicit reinstallation must succeed');
    },
  );
}

