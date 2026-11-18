import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/providers/directory_providers.dart';

/// Profile details plus the person's assigned tasks and meeting history.
final _teacherProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, uid) async {
  final sb = Supabase.instance.client;
  final p = await sb
      .from('profiles')
      .select('full_name, designation, employee_id, email, phone, bio, joining_date, is_active')
      .eq('id', uid)
      .single();
  final roleRows = await sb.from('user_roles').select('role').eq('user_id', uid);
  final deptRows = await sb
      .from('department_memberships')
      .select('departments(name)')
      .eq('user_id', uid);
  final roles = [for (final r in roleRows as List) r['role'] as String];
  final depts = [
    for (final r in deptRows as List)
      if ((r['departments'] as Map?)?['name'] != null) (r['departments'] as Map)['name'] as String,
  ];
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
    'roles': roles,
    'departments': depts,
    'tasks': alive(t as List, 'tasks'),
    'meetings': alive(m as List, 'meetings'),
  };
});

Widget _infoLine(IconData icon, String label, Object? value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_teacherProfileProvider(userId));
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <String>[];
    final theme = Theme.of(context);
    final canEdit = isSuperAdmin(roles);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff profile / প্রোফাইল'),
        actions: [
          if (canEdit)
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
          final staffRoles = (d['roles'] as List<String>);
          final depts = (d['departments'] as List<String>);
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
              _infoLine(Icons.badge_outlined, 'Employee ID / আইডি', p['employee_id']),
              _infoLine(Icons.mail_outline, 'Email / ইমেইল', p['email']),
              _infoLine(Icons.phone_outlined, 'Phone / ফোন', p['phone']),
              _infoLine(Icons.apartment_outlined, 'Department / বিভাগ',
                  depts.isEmpty ? null : depts.join(', ')),
              _infoLine(Icons.event_outlined, 'Joining date / যোগদান',
                  p['joining_date'] == null
                      ? null
                      : DateFormat('dd MMM yyyy').format(DateTime.parse(p['joining_date'] as String))),
              _infoLine(Icons.verified_user_outlined, 'Roles / ভূমিকা',
                  staffRoles.isEmpty ? null : staffRoles.map(prettyLabel).join(', ')),
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
