import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hon/app/hon_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/database_service.dart';

import 'package:hon/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.init(AppDatabase.inMemory());
  });

  testWidgets('HonApp loads and displays 5 bottom navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: HonApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 5 tabs exist
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });
}
