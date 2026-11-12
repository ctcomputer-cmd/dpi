import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Upcoming meetings visible to the current user (RLS applies).
/// The Meet link is entered manually by the organiser (fallback mode).
final _upcomingMeetingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('meetings')
      .select('id, title, starts_at, ends_at, meet_link, status')
      .isFilter('deleted_at', null)
      .gte('ends_at', DateTime.now().toUtc().toIso8601String())
      .order('starts_at', ascending: true)
      .limit(100);
  return List<Map<String, dynamic>>.from(rows as List);
});

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(_upcomingMeetingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meetings / সভা')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(_upcomingMeetingsProvider.future),
        child: meetings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [
            const SizedBox(height: 80),
            const Center(child: Text('Could not load meetings. / সভা লোড হয়নি।')),
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(_upcomingMeetingsProvider),
                child: const Text('Retry / আবার'),
              ),
            ),
          ]),
          data: (items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(child: Text('No upcoming meetings. / আসন্ন কোনো সভা নেই।')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final m = items[i];
                final start = DateTime.parse(m['starts_at'] as String).toLocal();
                final link = m['meet_link'] as String?;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.videocam_outlined),
                    title: Text(m['title'] as String),
                    subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(start)),
                    trailing: link == null || !link.startsWith('https://')
                        ? null
                        : IconButton(
                            tooltip: 'Join / যোগ দিন',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => launchUrl(
                              Uri.parse(link),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
