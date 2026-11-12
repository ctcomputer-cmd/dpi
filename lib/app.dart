import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/setup_required_screen.dart';
import 'features/home/home_shell.dart';
import 'features/home/dashboard_screen.dart';
import 'features/meetings/meetings_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/teachers/teachers_screen.dart';

/// Re-runs router redirects whenever the Supabase auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    if (AppConfig.isConfigured) {
      _sub = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) => notifyListeners());
    }
  }

  StreamSubscription<AuthState>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final _authRefresh = _AuthRefresh();

final appRouter = GoRouter(
  initialLocation: '/home',
  refreshListenable: _authRefresh,
  redirect: (context, state) {
    final loc = state.matchedLocation;

    if (!AppConfig.isConfigured) {
      return loc == '/setup' ? null : '/setup';
    }

    final loggedIn =
        Supabase.instance.client.auth.currentSession != null;
    final onAuthPage = loc == '/login';

    if (!loggedIn && !onAuthPage) return '/login';
    if (loggedIn && (onAuthPage || loc == '/setup')) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/setup', builder: (_, __) => const SetupRequiredScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
        GoRoute(path: '/meetings', builder: (_, __) => const MeetingsScreen()),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(path: '/teachers', builder: (_, __) => const TeachersScreen()),
      ],
    ),
  ],
);

class DpiDepartmentHubApp extends ConsumerWidget {
  const DpiDepartmentHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'DPI Department Hub',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
      // Bangla + English support. Full ARB translations are a Phase 2 task.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('bn')],
    );
  }
}
