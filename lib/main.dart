import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/hon_app.dart';
import 'core/database/database_service.dart';
import 'core/files/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge transparent system navigation
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Initialize core application services
  await StorageService.instance.init();
  await DatabaseService.instance.init();

  runApp(
    const ProviderScope(
      child: HonApp(),
    ),
  );
}
