import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Upcoming (not yet ended) meetings the user is allowed to see. RLS applies.
final upcomingMeetingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('meetings')
      .select('id, title, starts_at, ends_at, meet_link, status, department_id')
      .isFilter('deleted_at', null)
      .gte('ends_at', DateTime.now().toUtc().toIso8601String())
      .order('starts_at', ascending: true)
      .limit(100);
  return List<Map<String, dynamic>>.from(rows as List);
});
