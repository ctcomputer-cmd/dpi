import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../tasks/task_shared.dart';

/// One sub-task assignment, flattened for reporting.
class ReportRow {
  const ReportRow({
    required this.person,
    required this.task,
    required this.subtask,
    required this.deadline,
    required this.status,
    required this.progress,
  });

  final String person;
  final String task;
  final String subtask;
  final DateTime? deadline;
  final String status;
  final int progress;

  bool get overdue =>
      deadline != null && deadline!.isBefore(DateTime.now()) && status != 'completed';
}

/// Admins see every assignment (RLS). Other roles see only their own rows.
final reportRowsProvider = FutureProvider.autoDispose<List<ReportRow>>((ref) async {
  final sb = Supabase.instance.client;
  final subs = await sb
      .from('task_subtasks')
      .select('id, title, deadline, task_id')
      .isFilter('deleted_at', null);
  final tasks = await sb.from('tasks').select('id, title').isFilter('deleted_at', null);
  final rows = await sb
      .from('subtask_assignees')
      .select('subtask_id, user_id, status, progress_percent, '
          'profiles!subtask_assignees_user_id_fkey(full_name)');

  final subById = <String, Map<String, dynamic>>{
    for (final s in subs as List) (s['id'] as String): Map<String, dynamic>.from(s as Map),
  };
  final taskTitle = <String, String>{
    for (final t in tasks as List) (t['id'] as String): t['title'] as String,
  };

  final out = <ReportRow>[];
  for (final r in rows as List) {
    final s = subById[r['subtask_id'] as String];
    if (s == null) continue; // sub-task deleted
    out.add(ReportRow(
      person: nameOfRow(Map<String, dynamic>.from(r as Map)),
      task: taskTitle[s['task_id'] as String] ?? '',
      subtask: s['title'] as String,
      deadline: s['deadline'] == null
          ? null
          : DateTime.parse(s['deadline'] as String).toLocal(),
      status: r['status'] as String,
      progress: (r['progress_percent'] as int?) ?? 0,
    ));
  }
  out.sort((a, b) => a.person.compareTo(b.person));
  return out;
});

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _query = '';

  String _csv(List<ReportRow> rows) {
    String cell(String v) => '"${v.replaceAll('"', '""')}"';
    final lines = <String>[
      'Person,Task,Sub-task,Deadline,Status,Progress %,Overdue',
      for (final r in rows)
        [
          cell(r.person),
          cell(r.task),
          cell(r.subtask),
          cell(r.deadline == null ? '' : DateFormat('yyyy-MM-dd').format(r.deadline!)),
          cell(r.status),
          '${r.progress}',
          r.overdue ? 'yes' : 'no',
        ].join(','),
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reportRowsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports / রিপোর্ট'),
        actions: [
          IconButton(
            tooltip: 'Copy as CSV / CSV হিসেবে কপি',
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              final rows = async.valueOrNull;
              if (rows == null || rows.isEmpty) return;
              Clipboard.setData(ClipboardData(text: _csv(rows)));
              showMsg(context, 'Copied. Paste into Excel or Sheets. / কপি হয়েছে।');
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load report. / রিপোর্ট লোড হয়নি।'),
                const SizedBox(height: 8),
                Text('$e', style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => ref.invalidate(reportRowsProvider),
                  child: const Text('Retry / আবার'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) {
          final people = <String, List<ReportRow>>{};
          for (final r in rows) {
            people.putIfAbsent(r.person, () => []).add(r);
          }
          final names = people.keys
              .where((n) => _query.isEmpty || n.toLowerCase().contains(_query))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search person / নাম খুঁজুন',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No assignments yet. / এখনো কোনো দায়িত্ব নেই।',
                      textAlign: TextAlign.center),
                ),
              for (final name in names) _PersonCard(name: name, rows: people[name]!),
            ],
          );
        },
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.name, required this.rows});

  final String name;
  final List<ReportRow> rows;

  @override
  Widget build(BuildContext context) {
    final total = rows.length;
    final completed = rows.where((r) => r.status == 'completed').length;
    final overdue = rows.where((r) => r.overdue).length;
    final active = total - completed;
    final avg = rows.isEmpty
        ? 0
        : (rows.fold<int>(0, (s, r) => s + r.progress) / total).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: PersonAvatar(name: name, color: AppColors.secondary),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(text: '$total tasks', color: Colors.blueGrey),
              Pill(text: '$completed done', color: AppColors.success),
              Pill(text: '$active open', color: AppColors.secondary),
              if (overdue > 0)
                Pill(text: '$overdue overdue', color: AppColors.error, icon: Icons.warning_amber),
              Pill(text: 'Avg $avg%', color: Colors.orange.shade800),
            ],
          ),
        ),
        children: [
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text(r.subtask),
              subtitle: Text(
                '${r.task}\n'
                '${r.deadline == null ? 'No deadline' : 'Due ${DateFormat('dd MMM yyyy').format(r.deadline!)}'}'
                ' • ${r.progress}%',
              ),
              isThreeLine: true,
              trailing: StateChip(state: r.overdue ? 'overdue' : r.status),
            ),
        ],
      ),
    );
  }
}
