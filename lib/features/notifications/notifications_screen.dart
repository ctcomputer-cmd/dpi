import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/providers/data_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markRead(WidgetRef ref, String id) async {
    // RLS allows updating only the user's own notifications.
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true}).eq('id', id);
    ref.invalidate(notificationListProvider);
  }

  /// Marks the notification read (if needed) and opens the item it is about.
  Future<void> _open(BuildContext context, WidgetRef ref, NotificationItem n) async {
    try {
      if (!n.isRead) await _markRead(ref, n.id);
    } catch (_) {
      // Opening the item matters more than the read flag; ignore.
    }
    final link = n.link;
    if (link != null && context.mounted) context.push(link);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications / বিজ্ঞপ্তি'),
        actions: [
          IconButton(
            tooltip: 'Mark all read / সব পড়া হয়েছে',
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              try {
                // RLS limits this to the user's own notifications.
                await Supabase.instance.client
                    .from('notifications')
                    .update({'is_read': true})
                    .eq('is_read', false);
                ref.invalidate(notificationListProvider);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not update. / আপডেট হয়নি।')));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(notificationListProvider.future),
        child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [
            const SizedBox(height: 80),
            const Center(child: Text('Could not load notifications.')),
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(notificationListProvider),
                child: const Text('Retry / আবার'),
              ),
            ),
          ]),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(child: Text('No notifications. / কোনো বিজ্ঞপ্তি নেই।')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = list[i];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      n.isRead ? Icons.notifications_none : Icons.notifications_active,
                      color: n.isRead ? Colors.grey : Theme.of(context).colorScheme.secondary,
                    ),
                    title: Text(n.title,
                        style: TextStyle(
                            fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w700)),
                    subtitle: Text([
                      if (n.body != null) n.body!,
                      DateFormat('dd MMM, hh:mm a').format(n.createdAt.toLocal()),
                    ].join('\n')),
                    isThreeLine: n.body != null,
                    trailing: n.link == null ? null : const Icon(Icons.chevron_right),
                    onTap: () => _open(context, ref, n),
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
