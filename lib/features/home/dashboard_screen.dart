import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';
import 'my_tasks_section.dart';

/// Dashboard: counts come from the database. RLS limits rows to what the user may see.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <String>[];
    final isAdmin = roles.contains('super_admin') || roles.contains('principal');

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard / ড্যাশবোর্ড')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardStatsProvider.future),
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            message: 'Could not load data. Pull down to retry. / ডেটা লোড হয়নি।',
            onRetry: () => ref.invalidate(dashboardStatsProvider),
          ),
          data: (s) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _StatCard('Teachers / শিক্ষক', s.teachers, Icons.people, AppColors.secondary),
                  _StatCard('Active tasks / চলমান কাজ', s.activeTasks, Icons.pending_actions, AppColors.warning),
                  _StatCard('Completed / সম্পন্ন', s.completedTasks, Icons.check_circle, AppColors.success),
                  _StatCard('Overdue / মেয়াদোত্তীর্ণ', s.overdueTasks, Icons.warning_amber, AppColors.error),
                ],
              ),
              const SizedBox(height: 20),
              const MyTasksSection(),
              const SizedBox(height: 20),
              Text('Quick actions / দ্রুত কাজ',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                      avatar: const Icon(Icons.task_alt, size: 18),
                      label: const Text('My tasks / আমার কাজ'),
                      onPressed: () => context.go('/tasks')),
                  ActionChip(
                      avatar: const Icon(Icons.groups, size: 18),
                      label: const Text('Meetings / সভা'),
                      onPressed: () => context.go('/meetings')),
                  if (isAdmin)
                    ActionChip(
                        avatar: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Staff / কর্মী'),
                        onPressed: () => context.go('/teachers')),
                  if (isAdmin)
                    ActionChip(
                        avatar: const Icon(Icons.bar_chart, size: 18),
                        label: const Text('Reports / রিপোর্ট'),
                        onPressed: () => context.push('/reports')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon, this.color);

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text('$value',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 56, color: Colors.black38),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Retry / আবার')),
        ),
      ],
    );
  }
}
