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
}
