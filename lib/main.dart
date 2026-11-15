import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'shared/push_service.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  // Push notifications. If Firebase is not set up, the app still runs.
  try {
    await Firebase.initializeApp();
    listenPushTaps((link) => appRouter.push(link));
  } catch (_) {}

  runApp(const ProviderScope(child: DpiDepartmentHubApp()));
}
