// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router.dart';
import 'utils/constants.dart';
import 'services/data_service.dart';
import 'services/gebeta_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Fail loudly (not silently) if the map API key wasn't provided at build
  // time — without this, the map tiles won't load and every Gebeta call
  // just returns null, and the symptom looks like "the map is broken" with
  // no clue why.
  if (GebetaService.isApiKeyMissing && kDebugMode) {
    debugPrint(
      '⚠️  GEBETA_API_KEY is not set. The map, geocoding, and directions '
      'will silently fail. Run with:\n'
      '   flutter run --dart-define=GEBETA_API_KEY=your_key\n'
      'or --dart-define-from-file=dart_defines.json (see dart_defines.example.json).',
    );
  }

  // Expire any package requests that nobody accepted within 2 hours
  DataService().expireOldRequests();

  runApp(const ProviderScope(child: BemengedeApp()));
}

class BemengedeApp extends ConsumerWidget {
  const BemengedeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Bemengede',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(AppColors.primary),
          brightness: Brightness.light,
        ),
        fontFamily: 'Inter',
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(AppColors.primary),
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
