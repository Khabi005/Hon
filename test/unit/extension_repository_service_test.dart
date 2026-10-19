import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/sources/extension_repository_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('adds an HTTPS Shosetsu index and persists its catalog', () async {
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
        '''{
        "scripts": [
          {"id": 42, "name": "Example", "lang": "eng", "fileName": "Example", "ver": "1.2.3", "libVer": "1.0.0"},
          {"id": 43, "name": "Unsafe", "lang": "../tmp", "fileName": "bad", "ver": "1.0.0"}
        ],
        "libraries": []
      }''',
        200,
        request: request,
      );
    });
    final service = ExtensionRepositoryService(client: client);
    await service.init();
    final repository = await service.add(
      'Example Repo',
      'https://example.org/ext',
    );

    expect(requested.toString(), 'https://example.org/ext/index.json');
    expect(repository.scripts.single.name, 'Example');
    expect(repository.scripts.single.id, '42');
    await expectLater(
      service.add('Duplicate', repository.url),
      throwsFormatException,
    );

    final reopened = ExtensionRepositoryService(client: client);
    await reopened.init();
    expect(reopened.repositories.single.scripts.single.fileName, 'Example');
    await reopened.remove(repository.id);
    expect(reopened.repositories, isEmpty);
  });

  test(
    'rejects insecure URLs and leaves existing catalog on failed refresh',
    () async {
      var failing = false;
      final client = MockClient(
        (request) async => http.Response(
          failing ? 'temporary error' : '{"scripts": []}',
          failing ? 503 : 200,
          request: request,
        ),
      );
      final service = ExtensionRepositoryService(client: client);
      await service.init();
      await expectLater(
        service.add('Insecure', 'http://example.org/repo'),
        throwsFormatException,
      );
      final repository = await service.add('Safe', 'https://example.org/repo/');
      failing = true;
      await expectLater(service.refresh(repository.id), throwsFormatException);
      expect(service.repositories.single.refreshedAt, repository.refreshedAt);
    },
  );

  test('a damaged saved catalog does not prevent app startup', () async {
    SharedPreferences.setMockInitialValues({
      'hon_extension_repositories_v1': '{broken',
    });
    final service = ExtensionRepositoryService(
      client: MockClient(
        (request) async =>
            http.Response('{"scripts": []}', 200, request: request),
      ),
    );
    await service.init();
    expect(service.repositories, isEmpty);
    expect(service.loadError, isNotNull);
  });

  test('RepositoryScript.fromJson resolves relative iconUrl and collects allowedHosts', () {
    final script = RepositoryScript.fromJson({
      'id': '100',
      'name': 'Test Script',
      'lang': 'en',
      'fileName': 'test_script',
      'ver': '1.0.0',
      'imageURL': 'icons/test_script.png',
      'allowedHosts': ['api.testscript.com'],
      'hosts': ['cdn.testscript.com'],
    }, baseUrl: 'https://repo.shosetsu.app/repo/');

    expect(script.iconUrl, 'https://repo.shosetsu.app/repo/icons/test_script.png');
    expect(script.allowedHosts, contains('api.testscript.com'));
    expect(script.allowedHosts, contains('cdn.testscript.com'));
    expect(script.allowedHosts, contains('repo.shosetsu.app'));
  });
}
