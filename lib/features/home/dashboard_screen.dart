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
    final superAdmin = isSuperAdmin(roles);
    final canReport = superAdmin || roles.contains('principal');

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
              if (superAdmin) ...[
                const SizedBox(height: 20),
                const _AddStaffCard(),
              ],
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
                  ActionChip(
                      avatar: const Icon(Icons.badge_outlined, size: 18),
                      label: const Text('Staff directory / কর্মী তালিকা'),
                      onPressed: () => context.go('/teachers')),
                  if (canReport)
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

/// Shown to super admins only: where to add a new employee and what to enter.
class _AddStaffCard extends StatelessWidget {
  const _AddStaffCard();

  @override
  Widget build(BuildContext context) {
    const fields = [
      'Full name / পূর্ণ নাম',
      'Email (login link is sent here) / ইমেইল',
      'Employee ID / কর্মী আইডি',
      'Designation / পদবি',
      'Department / বিভাগ',
      'Phone / ফোন',
      'Joining date / যোগদানের তারিখ',
      'Roles / ভূমিকা',
      'Short bio / সংক্ষিপ্ত পরিচিতি',
    ];
    return Card(
      color: AppColors.secondary.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_add_alt_1, color: AppColors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Add new employee / নতুন কর্মী যোগ করুন',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary,
                          )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Enter these details / এই তথ্যগুলো লিখুন:',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 6),
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/teachers/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add employee / কর্মী যোগ করুন'),
              ),
            ),
          ],
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
