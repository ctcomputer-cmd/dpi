import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/providers/meeting_providers.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(upcomingMeetingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meetings / সভা')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New / নতুন'),
        onPressed: () async {
          await context.push('/meetings/new');
          ref.invalidate(upcomingMeetingsProvider);
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(upcomingMeetingsProvider.future),
        child: meetings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [
            const SizedBox(height: 80),
            const Center(child: Text('Could not load meetings. / সভা লোড হয়নি।')),
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(upcomingMeetingsProvider),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
                    onTap: () async {
                      await context.push('/meetings/${m['id']}/edit');
                      ref.invalidate(upcomingMeetingsProvider);
                    },
                    trailing: (link == null || !link.startsWith('https://'))
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
