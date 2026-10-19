import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/sources/extension_repository_service.dart';
import 'package:hon/features/settings/presentation/extension_repositories_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'repository dialog survives cancel, submit and failed add transitions',
    (tester) async {
      var fail = false;
      final service = ExtensionRepositoryService(
        client: MockClient(
          (request) async => http.Response(
            fail ? 'offline' : '{"scripts": []}',
            fail ? 503 : 200,
            request: request,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExtensionRepositoriesScreen(repositoryService: service),
        ),
      );
      for (final submit in [false, true, true]) {
        await tester.tap(find.text('Add repository'));
        await tester.pumpAndSettle();
        expect(
          find.byType(TextField),
          findsNWidgets(2),
          reason: 'submit=$submit fail=$fail',
        );
        await tester.enterText(find.byType(TextField).first, 'Sample');
        await tester.enterText(
          find.byType(TextField).last,
          'https://example.org/${fail ? 'failed' : 'repo'}/',
        );
        await tester.tap(find.text(submit ? 'Add' : 'Cancel').last);
        await tester.pump();
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (submit) fail = true;
      }
      expect(service.repositories.length, 1);
      expect(find.textContaining('Could not add repository'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      service.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
