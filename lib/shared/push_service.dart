import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _refreshListening = false;

/// Saves this phone's push token for the signed-in user, so the server can
/// send notifications to it. Any failure is ignored: a push setup problem must
/// never stop the app from working.
Future<void> registerPushToken() async {
  try {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) await _saveToken(token);
    if (!_refreshListening) {
      _refreshListening = true;
      messaging.onTokenRefresh.listen(_saveToken);
    }
  } catch (_) {
    // Firebase not set up on this build: skip silently.
  }
}

Future<void> _saveToken(String token) async {
  try {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    await sb.from('device_tokens').upsert({
      'token': token,
      'user_id': uid,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  } catch (_) {
    // Try again on the next login or token refresh.
  }
}

/// Opens the in-app link carried by a push notification when the user taps it.
/// Handles both: app in background (onMessageOpenedApp) and app closed (initial message).
void listenPushTaps(void Function(String link) open) {
  try {
    void handle(RemoteMessage m) {
      final link = m.data['link'];
      if (link is String && link.isNotEmpty) open(link);
    }

    FirebaseMessaging.onMessageOpenedApp.listen(handle);
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) handle(m);
    }).catchError((_) {});
  } catch (_) {
    // Firebase not set up on this build: skip silently.
  }
}
