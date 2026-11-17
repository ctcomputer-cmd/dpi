import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Creates a Google Meet link through the Google Calendar API.
///
/// The organizer signs in with their own Google account (no Workspace admin
/// setup needed). The event is created on their primary calendar with a
/// Meet conference attached, and the Meet URL is returned.
class GoogleMeet {
  GoogleMeet._();

  static final _google = GoogleSignIn(
    scopes: const ['https://www.googleapis.com/auth/calendar.events'],
  );

  /// Returns a `https://meet.google.com/...` link, or throws on failure.
  static Future<String> createLink({
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    // Always show the account picker so the organizer can choose the right account.
    await _google.signOut();
    final account = await _google.signIn();
    if (account == null) {
      throw const GoogleMeetException('Sign-in cancelled. / সাইন-ইন বাতিল হয়েছে।');
    }
    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) {
      throw const GoogleMeetException('No access token. / অ্যাক্সেস টোকেন পাওয়া যায়নি।');
    }

    final body = {
      'summary': title,
      'start': {'dateTime': start.toUtc().toIso8601String(), 'timeZone': 'UTC'},
      'end': {'dateTime': end.toUtc().toIso8601String(), 'timeZone': 'UTC'},
      'conferenceData': {
        'createRequest': {
          'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
          'conferenceSolutionKey': {'type': 'hangoutsMeet'},
        },
      },
    };

    final res = await http.post(
      Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GoogleMeetException(
          'Google error ${res.statusCode}. / গুগল ত্রুটি ${res.statusCode}।');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final link = (json['hangoutLink'] as String?) ??
        ((json['conferenceData']?['entryPoints'] as List?) ?? const [])
            .cast<Map>()
            .where((e) => e['entryPointType'] == 'video')
            .map((e) => e['uri'] as String?)
            .firstWhere((u) => u != null, orElse: () => null);
    if (link == null) {
      throw const GoogleMeetException(
          'Meet link not returned. / মিট লিংক পাওয়া যায়নি।');
    }
    return link;
  }
}

class GoogleMeetException implements Exception {
  const GoogleMeetException(this.message);
  final String message;
  @override
  String toString() => message;
}
