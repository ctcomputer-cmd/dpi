import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';

/// Tasks where the signed-in user is an assignee. Progress is the task's overall
/// progress, the same number the task details page shows.
final myAssignedTasksProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return <Map<String, dynamic>>[];
  final rows = await Supabase.instance.client
      .from('task_assignees')
      .select('tasks(id, title, deadline, status, deleted_at, progress_percent)')
      .eq('user_id', uid)
      .limit(100);
  return List<Map<String, dynamic>>.from(rows as List).where((r) {
    final t = r['tasks'] as Map<String, dynamic>?;
    return t != null && t['deleted_at'] == null;
  }).toList();
});

const _closed = ['completed', 'cancelled'];

class MyTasksSection extends ConsumerWidget {
  const MyTasksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myAssignedTasksProvider);
    final all = ref.watch(taskListProvider);
    final now = DateTime.now();
    final overdue = (all.valueOrNull ?? const <TaskItem>[])
        .where((t) =>
            t.deadline != null && t.deadline!.isBefore(now) && !_closed.contains(t.status))
        .toList();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My assigned tasks / আমার কাজ', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        mine.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load your tasks. / কাজ লোড হয়নি।'),
          data: (list) {
            final open = list
                .where((r) => !_closed.contains((r['tasks'] as Map)['status']))
                .toList();
            if (open.isEmpty) {
              return const Text('No open tasks. / খোলা কাজ নেই।');
            }
            return Column(
              children: [
                for (final r in open.take(5))
                  Card(
                    child: ListTile(
                      title: Text((r['tasks'] as Map)['title'] as String),
                      subtitle: Text(
                          '${prettyLabel((r['tasks'] as Map)['status'] as String)} • '
                          '${(r['tasks'] as Map)['progress_percent'] ?? 0}%'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/tasks/${(r['tasks'] as Map)['id']}'),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text('Overdue / মেয়াদ শেষ', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (overdue.isEmpty)
          const Text('Nothing overdue. / কিছু মেয়াদ শেষ হয়নি।')
        else
          Column(
            children: [
              for (final t in overdue.take(5))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber, color: AppColors.error),
                    title: Text(t.title),
                    subtitle: Text(
                        'Due ${DateFormat('dd MMM yyyy').format(t.deadline!.toLocal())}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/tasks/${t.id}'),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
