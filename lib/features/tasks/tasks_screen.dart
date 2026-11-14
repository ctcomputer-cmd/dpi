import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/providers/data_providers.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks / কাজ')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New / নতুন'),
        onPressed: () async {
          await context.push('/tasks/new');
          ref.invalidate(taskListProvider);
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(taskListProvider.future),
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [
            const SizedBox(height: 80),
            const Center(
                child: Text('Could not load tasks. / কাজ লোড হয়নি।')),
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(taskListProvider),
                child: const Text('Retry / আবার'),
              ),
            ),
          ]),
          data: (items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(child: Text('No tasks yet. / এখনো কোনো কাজ নেই।')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _TaskTile(
                item: items[i],
                onTap: () async {
                  await context.push('/tasks/${items[i].id}/edit');
                  ref.invalidate(taskListProvider);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.item, this.onTap});

  final TaskItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final overdue = item.deadline != null &&
        item.deadline!.isBefore(DateTime.now()) &&
        item.status != 'completed' &&
        item.status != 'cancelled';

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            _statusLabel(item.status),
            if (item.deadline != null)
              'Due ${DateFormat('dd MMM yyyy').format(item.deadline!.toLocal())}',
          ].join(' • '),
          style: TextStyle(color: overdue ? AppColors.error : null),
        ),
        trailing: _PriorityChip(priority: item.priority),
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'not_started' => 'Not started',
        'in_progress' => 'In progress',
        'under_review' => 'Under review',
        'revision_required' => 'Revision required',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => s,
      };
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'urgent' => AppColors.error,
      'high' => AppColors.warning,
      'medium' => AppColors.secondary,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(priority.toUpperCase(), style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      labelStyle: TextStyle(color: color),
    );
  }
}
