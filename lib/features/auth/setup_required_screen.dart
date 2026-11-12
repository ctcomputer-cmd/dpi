import 'package:flutter/material.dart';

/// Shown when the app was built without SUPABASE_URL / SUPABASE_ANON_KEY.
/// This prevents a silently broken app from being shipped.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_suggest_outlined, size: 64),
              SizedBox(height: 16),
              Text(
                'Backend not configured',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'This build is missing SUPABASE_URL and SUPABASE_ANON_KEY.\n'
                'See docs/SETUP.md for build instructions.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
