import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

// ---------- client helpers ----------

SupabaseClient get taskSb => Supabase.instance.client;

String get taskMe => taskSb.auth.currentUser!.id;

List<Map<String, dynamic>> asRows(dynamic v) =>
    v == null ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(v as List);

int progressOf(Map<String, dynamic> row) => (row['progress_percent'] as int?) ?? 0;

String nameOfRow(Map<String, dynamic> row) =>
    ((row['profiles'] as Map?)?['full_name'] as String?) ?? 'Unknown';

String errorText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return e.message;
  return 'Network error. / নেটওয়ার্ক সমস্যা।';
}

void showMsg(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> logTaskActivity(String taskId, String action, [Map<String, dynamic>? details]) async {
  await taskSb.from('task_activity_logs').insert({
    'task_id': taskId,
    'actor_id': taskMe,
    'action': action,
    'details': details ?? <String, dynamic>{},
  });
}

/// Creator, admins and department heads/coordinators may manage a task.
/// (The database enforces this too; the UI only hides buttons.)
bool canManageTaskUi(String createdBy, List<String> roles) =>
    createdBy == taskMe ||
    roles.any((r) => r == 'super_admin' || r == 'principal' || r == 'hod' || r == 'coordinator');

// ---------- status styling ----------

class StateStyle {
  const StateStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// One colour per meaning, used everywhere in the task screens:
/// grey = not started, blue = in progress, amber = waiting for review,
/// purple = revision needed, green = done, red = overdue.
const kColorNotStarted = Color(0xFF64748B);
const kColorReview = Color(0xFFD97706);
const kColorRevision = Color(0xFF9333EA);

StateStyle stateStyle(String state) {
  switch (state) {
    case 'completed':
      return StateStyle('Completed / সম্পন্ন', AppColors.success, Icons.check_circle);
    case 'under_review':
      return StateStyle('Under review / যাচাই চলছে', kColorReview, Icons.hourglass_top);
    case 'revision_required':
      return StateStyle('Revision / সংশোধন দরকার', kColorRevision, Icons.replay);
    case 'in_progress':
      return StateStyle('In progress / চলছে', AppColors.secondary, Icons.autorenew);
    case 'unassigned':
      return StateStyle('Not assigned / বরাদ্দ নেই', kColorNotStarted, Icons.person_off_outlined);
    case 'overdue':
      return StateStyle('Overdue / মেয়াদোত্তীর্ণ', AppColors.error, Icons.warning_amber);
    case 'cancelled':
      return StateStyle('Cancelled / বাতিল', Colors.grey, Icons.cancel_outlined);
    default:
      return StateStyle('Not started / শুরু হয়নি', kColorNotStarted, Icons.radio_button_unchecked);
  }
}

String initialOf(String name) =>
    name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

/// A sub-task's state, worked out from the people assigned to it.
String subtaskState(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return 'unassigned';
  if (rows.every((r) => r['status'] == 'completed')) return 'completed';
  if (rows.any((r) => r['status'] == 'revision_required')) return 'revision_required';
  if (rows.any((r) => r['status'] == 'under_review')) return 'under_review';
  if (rows.any((r) => progressOf(r) > 0)) return 'in_progress';
  return 'not_started';
}

int avgProgress(List<Map<String, dynamic>> rows) => rows.isEmpty
    ? 0
    : (rows.fold<int>(0, (sum, r) => sum + progressOf(r)) / rows.length).round();

Color priorityColor(String p) {
  switch (p) {
    case 'urgent':
      return Colors.red.shade700;
    case 'high':
      return Colors.orange.shade800;
    case 'medium':
      return AppColors.secondary;
    default:
      return Colors.blueGrey;
  }
}

class DeadlineInfo {
  const DeadlineInfo(this.text, this.color, this.overdue);
  final String text;
  final Color color;
  final bool overdue;
}

DeadlineInfo deadlineInfo(String? iso, {bool done = false}) {
  if (iso == null) {
    return DeadlineInfo('No deadline / সময়সীমা নেই', Colors.blueGrey, false);
  }
  final d = DateTime.parse(iso).toLocal();
  final text = DateFormat('dd MMM yyyy').format(d);
  if (done) return DeadlineInfo('Due $text', AppColors.success, false);
  final now = DateTime.now();
  if (d.isBefore(now)) return DeadlineInfo('Overdue • $text', AppColors.error, true);
  if (d.difference(now).inHours < 48) {
    return DeadlineInfo('Soon • $text', Colors.orange.shade800, false);
  }
  return DeadlineInfo('Due $text', Colors.blueGrey.shade700, false);
}

// ---------- models ----------

typedef SubKey = ({String taskId, String subtaskId});
typedef DiscussionKey = ({String taskId, String? subtaskId});

class TaskDetail {
  const TaskDetail({
    required this.task,
    required this.subtasks,
    required this.attachments,
    required this.activity,
    required this.creatorName,
  });

  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> subtasks;
  final List<Map<String, dynamic>> attachments;
  final List<Map<String, dynamic>> activity;
  final String creatorName;

  static List<Map<String, dynamic>> assigneesOf(Map<String, dynamic> subtask) =>
      asRows(subtask['subtask_assignees']);

  /// Stored by the database (same value as the dashboard); computed as a fallback.
  int get overallProgress {
    final stored = task['progress_percent'];
    if (stored is int) return stored;
    final all = [for (final s in subtasks) ...assigneesOf(s)];
    return avgProgress(all);
  }

  int get completedSubtasks =>
      subtasks.where((s) => subtaskState(assigneesOf(s)) == 'completed').length;

  /// Everyone responsible for any sub-task, without repeats.
  List<String> get responsibleNames {
    final names = <String>{
      for (final s in subtasks)
        for (final r in assigneesOf(s)) nameOfRow(r),
    }..removeWhere((n) => n == 'Unknown');
    return names.toList()..sort();
  }
}

class SubtaskDetail {
  const SubtaskDetail({
    required this.subtask,
    required this.assignees,
    required this.taskTitle,
    required this.createdBy,
  });

  final Map<String, dynamic> subtask;
  final List<Map<String, dynamic>> assignees;
  final String taskTitle;
  final String createdBy;

  int get progress => avgProgress(assignees);
  String get state => subtaskState(assignees);
}

// ---------- providers ----------

final taskDetailProvider =
    FutureProvider.autoDispose.family<TaskDetail, String>((ref, id) async {
  final t = await taskSb.from('tasks').select().eq('id', id).single();
  final subs = await taskSb
      .from('task_subtasks')
      .select('id, title, description, deadline, created_at, '
          'subtask_assignees(user_id, progress_percent, status, '
          'profiles!subtask_assignees_user_id_fkey(full_name))')
      .eq('task_id', id)
      .isFilter('deleted_at', null)
      .order('created_at');
  final f = await taskSb
      .from('task_attachments')
      .select('id, file_name, storage_path, created_at')
      .eq('task_id', id)
      .order('created_at');
  final l = await taskSb
      .from('task_activity_logs')
      .select('action, details, created_at, profiles(full_name)')
      .eq('task_id', id)
      .order('created_at', ascending: false)
      .limit(30);
  final creator = await taskSb
      .from('profiles')
      .select('full_name')
      .eq('id', t['created_by'] as String)
      .maybeSingle();

  return TaskDetail(
    task: Map<String, dynamic>.from(t),
    subtasks: asRows(subs),
    attachments: asRows(f),
    activity: asRows(l),
    creatorName: (creator?['full_name'] as String?) ?? '',
  );
});

final subtaskDetailProvider =
    FutureProvider.autoDispose.family<SubtaskDetail, SubKey>((ref, key) async {
  final s = await taskSb
      .from('task_subtasks')
      .select('id, title, description, deadline, created_by')
      .eq('id', key.subtaskId)
      .single();
  final a = await taskSb
      .from('subtask_assignees')
      .select('user_id, progress_percent, status, submission_note, submitted_at, '
          'review_note, reviewed_at, profiles!subtask_assignees_user_id_fkey(full_name)')
      .eq('subtask_id', key.subtaskId);
  final t = await taskSb
      .from('tasks')
      .select('title, created_by')
      .eq('id', key.taskId)
      .single();

  return SubtaskDetail(
    subtask: Map<String, dynamic>.from(s),
    assignees: asRows(a),
    taskTitle: t['title'] as String,
    createdBy: t['created_by'] as String,
  );
});

final discussionProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DiscussionKey>((ref, key) async {
  final base = taskSb
      .from('task_comments')
      .select('id, body, author_id, created_at, profiles(full_name)')
      .eq('task_id', key.taskId);
  final rows = key.subtaskId == null
      ? await base.isFilter('subtask_id', null).order('created_at')
      : await base.eq('subtask_id', key.subtaskId!).order('created_at');
  return asRows(rows);
});

// ---------- small widgets ----------

class Pill extends StatelessWidget {
  const Pill({super.key, required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class StateChip extends StatelessWidget {
  const StateChip({super.key, required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final s = stateStyle(state);
    return Pill(text: s.label, color: s.color, icon: s.icon);
  }
}

/// A labelled line: icon, label on the left, value on the right.
/// Used so deadline, creator and responsible people are never guessed from colour.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF334155);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      ),
    );
  }
}

/// Responsible people as named chips (initial + full name). Empty = a clear warning.
class ResponsibleChips extends StatelessWidget {
  const ResponsibleChips({super.key, required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return const Pill(
        text: 'No one assigned / কেউ নেই',
        color: kColorNotStarted,
        icon: Icons.person_off_outlined,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in names)
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.secondary,
                  child: Text(initialOf(n),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                Text(n,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary)),
              ],
            ),
          ),
      ],
    );
  }
}

class ProgressStrip extends StatelessWidget {
  const ProgressStrip({super.key, required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: percent / 100,
        minHeight: 8,
        color: color,
        backgroundColor: Colors.grey.shade200,
      ),
    );
  }
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.color, this.radius = 16});

  final String name;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name.isEmpty ? '?' : name,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: color.withOpacity(0.15),
        child: Text(
          initialOf(name),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ---------- discussion ----------

/// Message thread. With subtaskId it is that sub-task's thread; without it,
/// the main task's general thread.
class DiscussionSection extends ConsumerStatefulWidget {
  const DiscussionSection({super.key, required this.taskId, this.subtaskId});

  final String taskId;
  final String? subtaskId;

  @override
  ConsumerState<DiscussionSection> createState() => _DiscussionSectionState();
}

class _DiscussionSectionState extends ConsumerState<DiscussionSection> {
  final _input = TextEditingController();
  bool _sending = false;

  DiscussionKey get _key => (taskId: widget.taskId, subtaskId: widget.subtaskId);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await taskSb.from('task_comments').insert({
        'task_id': widget.taskId,
        'subtask_id': widget.subtaskId,
        'author_id': taskMe,
        'body': text,
      });
      _input.clear();
      ref.invalidate(discussionProvider(_key));
    } catch (e) {
      if (mounted) showMsg(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(discussionProvider(_key));
    final me = taskMe;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        messages.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => TextButton(
            onPressed: () => ref.invalidate(discussionProvider(_key)),
            child: const Text('Could not load. Retry / আবার'),
          ),
          data: (rows) => rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No messages yet. / এখনো কোনো আলোচনা নেই।'),
                )
              : Column(
                  children: [
                    for (final c in rows) _Bubble(comment: c, mine: c['author_id'] == me),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write a message / আলোচনা লিখুন',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Send / পাঠান',
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.comment, required this.mine});

  final Map<String, dynamic> comment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final name = ((comment['profiles'] as Map?)?['full_name'] as String?) ?? 'Unknown';
    final when = DateTime.parse(comment['created_at'] as String).toLocal();
    final color = mine ? AppColors.secondary : Colors.blueGrey;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$name • ${DateFormat('dd MMM, hh:mm a').format(when)}',
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(comment['body'] as String),
          ],
        ),
      ),
    );
  }
}
