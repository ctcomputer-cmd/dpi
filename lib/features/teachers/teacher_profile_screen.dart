import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/providers/directory_providers.dart';

/// Profile details plus the person's assigned tasks and meeting history.
final _teacherProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, uid) async {
  final sb = Supabase.instance.client;
  final p = await sb
      .from('profiles')
      .select('full_name, designation, employee_id, email, phone, bio, is_active')
      .eq('id', uid)
      .single();
  final t = await sb
      .from('task_assignees')
      .select('progress_percent, status, tasks(id, title, deadline, status, deleted_at)')
      .eq('user_id', uid)
      .limit(100);
  final m = await sb
      .from('meeting_participants')
      .select('meetings(id, title, starts_at, status, deleted_at)')
      .eq('user_id', uid)
      .limit(100);

  List<Map<String, dynamic>> alive(List rows, String key) => List<Map<String, dynamic>>.from(rows)
      .where((r) => (r[key] as Map?)?['deleted_at'] == null && r[key] != null)
      .toList();

  return {
    'profile': Map<String, dynamic>.from(p),
    'tasks': alive(t as List, 'tasks'),
    'meetings': alive(m as List, 'meetings'),
  };
});

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_teacherProfileProvider(userId));
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <String>[];
    final isAdmin = roles.contains('super_admin') || roles.contains('principal');
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff profile / প্রোফাইল'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Edit / সম্পাদনা',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push('/teachers/$userId/edit');
                ref.invalidate(_teacherProfileProvider(userId));
              },
            ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load profile.\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (d) {
          final p = d['profile'] as Map<String, dynamic>;
          final tasks = d['tasks'] as List<Map<String, dynamic>>;
          final meetings = d['meetings'] as List<Map<String, dynamic>>;
          final name = (p['full_name'] as String?) ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 36,
                  child: Text(name.isEmpty ? '?' : name.substring(0, 1),
                      style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(name, style: theme.textTheme.titleLarge)),
              if (p['designation'] != null)
                Center(child: Text(p['designation'] as String)),
              const SizedBox(height: 16),
              if (p['employee_id'] != null) Text('ID: ${p['employee_id']}'),
              if (p['email'] != null) Text('Email: ${p['email']}'),
              if (p['phone'] != null) Text('Phone: ${p['phone']}'),
              if (p['bio'] != null) ...[
                const SizedBox(height: 8),
                Text(p['bio'] as String),
              ],
              if (p['is_active'] == false)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Inactive account / নিষ্ক্রিয়'),
                ),
              const SizedBox(height: 20),
              Text('Assigned tasks / কাজসমূহ', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              if (tasks.isEmpty) const Text('No tasks. / কোনো কাজ নেই।'),
              for (final r in tasks)
                Card(
                  child: ListTile(
                    title: Text((r['tasks'] as Map)['title'] as String),
                    subtitle: Text(
                        '${prettyLabel(r['status'] as String)} • ${r['progress_percent']}%'),
                    onTap: () => context.push('/tasks/${(r['tasks'] as Map)['id']}'),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Meetings / সভা', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              if (meetings.isEmpty) const Text('No meetings. / কোনো সভা নেই।'),
              for (final r in meetings)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text((r['meetings'] as Map)['title'] as String),
                    subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(
                        DateTime.parse((r['meetings'] as Map)['starts_at'] as String).toLocal())),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
