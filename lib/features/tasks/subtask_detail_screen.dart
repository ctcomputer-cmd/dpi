import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/providers/directory_providers.dart';
import 'task_shared.dart';

/// One sub-task: who has it, progress, submit / review, and its own discussion.
class SubtaskDetailScreen extends ConsumerStatefulWidget {
  const SubtaskDetailScreen({super.key, required this.taskId, required this.subtaskId});

  final String taskId;
  final String subtaskId;

  @override
  ConsumerState<SubtaskDetailScreen> createState() => _SubtaskDetailScreenState();
}

class _SubtaskDetailScreenState extends ConsumerState<SubtaskDetailScreen> {
  bool _busy = false;
  double? _slider;

  SubKey get _key => (taskId: widget.taskId, subtaskId: widget.subtaskId);

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(subtaskDetailProvider(_key));
    ref.invalidate(taskDetailProvider(widget.taskId));
  }

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && ok != null) showMsg(context, ok);
    } catch (e) {
      if (mounted) showMsg(context, errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _slider = null;
        });
      }
      _refresh();
    }
  }

  String get _title =>
      ref.read(subtaskDetailProvider(_key)).valueOrNull?.subtask['title'] as String? ?? '';

  Future<void> _saveProgress(int value, String currentStatus) => _run(() async {
        final update = <String, dynamic>{'progress_percent': value};
        if (value > 0 && (currentStatus == 'not_started' || currentStatus == 'revision_required')) {
          update['status'] = 'in_progress';
        }
        await taskSb
            .from('subtask_assignees')
            .update(update)
            .eq('subtask_id', widget.subtaskId)
            .eq('user_id', taskMe);
        await logTaskActivity(widget.taskId, 'progress_updated',
            {'subtask': _title, 'progress': value});
      }, ok: 'Progress saved / অগ্রগতি সংরক্ষিত');

  Future<String?> _askText(String title) async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Note / নোট (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    return result;
  }

  Future<void> _submit() async {
    final note = await _askText('Submit for review / জমা দিন');
    if (note == null) return;
    await _run(() async {
      await taskSb.from('subtask_assignees').update({
        'status': 'under_review',
        'progress_percent': 100,
        'submission_note': note.isEmpty ? null : note,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('subtask_id', widget.subtaskId).eq('user_id', taskMe);
      await logTaskActivity(widget.taskId, 'submitted_for_review', {'subtask': _title});
    }, ok: 'Submitted / জমা দেওয়া হয়েছে');
  }

  Future<void> _review(String userId, {required bool approve}) async {
    final note = await _askText(
        approve ? 'Approve / অনুমোদন' : 'Ask for revision / সংশোধন চান');
    if (note == null) return;
    if (!approve && note.isEmpty) {
      if (mounted) showMsg(context, 'Please write what to fix. / কী সংশোধন দরকার লিখুন।');
      return;
    }
    await _run(() async {
      await taskSb.from('subtask_assignees').update({
        'status': approve ? 'completed' : 'revision_required',
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': taskMe,
        'review_note': note.isEmpty ? null : note,
      }).eq('subtask_id', widget.subtaskId).eq('user_id', userId);
      await logTaskActivity(
          widget.taskId, approve ? 'approved' : 'revision_requested', {'subtask': _title});

      if (approve) await _closeTaskIfAllDone();
    }, ok: approve ? 'Approved / অনুমোদিত' : 'Revision requested / সংশোধনের অনুরোধ');
  }

  /// When every sub-task is fully approved, mark the main task completed.
  Future<void> _closeTaskIfAllDone() async {
    final rows = await taskSb
        .from('task_subtasks')
        .select('id, subtask_assignees(status)')
        .eq('task_id', widget.taskId)
        .isFilter('deleted_at', null);
    final subs = asRows(rows);
    final allDone = subs.isNotEmpty &&
        subs.every((s) {
          final people = TaskDetail.assigneesOf(s);
          return people.isNotEmpty && people.every((p) => p['status'] == 'completed');
        });
    if (allDone) {
      await taskSb
          .from('tasks')
          .update({'status': 'completed', 'updated_by': taskMe}).eq('id', widget.taskId);
    }
  }

  Future<void> _deleteSubtask() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete sub-task? / উপ-কাজ মুছবেন?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await taskSb.from('task_subtasks').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.subtaskId);
      await logTaskActivity(widget.taskId, 'subtask_deleted', {'subtask': _title});
      ref.invalidate(taskDetailProvider(widget.taskId));
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/tasks/${widget.taskId}');
      }
    } catch (e) {
      if (mounted) showMsg(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subtaskDetailProvider(_key));
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <String>[];
    final loaded = async.valueOrNull;
    final canManage = loaded != null && canManageTaskUi(loaded.createdBy, roles);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sub-task / উপ-কাজ'),
        leading: IconButton(
          tooltip: 'Back / পিছনে',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Edit / সম্পাদনা',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context
                    .push('/tasks/${widget.taskId}/subtasks/${widget.subtaskId}/edit');
                _refresh();
              },
            ),
          if (canManage)
            IconButton(
              tooltip: 'Delete / মুছুন',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSubtask,
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
                const Text('Could not load. / লোড হয়নি।'),
                const SizedBox(height: 8),
                Text('$e', style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                TextButton(onPressed: _refresh, child: const Text('Retry / আবার')),
              ],
            ),
          ),
        ),
        data: (d) => AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: _content(context, d, canManage),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, SubtaskDetail d, bool canManage) {
    final theme = Theme.of(context);
    final me = taskMe;
    final state = d.state;
    final style = stateStyle(state);
    final dl = deadlineInfo(d.subtask['deadline'] as String?, done: state == 'completed');
    final desc = (d.subtask['description'] as String?) ?? '';

    Map<String, dynamic>? mine;
    for (final r in d.assignees) {
      if (r['user_id'] == me) mine = r;
    }

    return [
      // ---- Header ----
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.taskTitle,
                  style: theme.textTheme.labelLarge?.copyWith(color: Colors.blueGrey)),
              const SizedBox(height: 4),
              Text(
                d.subtask['title'] as String,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StateChip(state: state),
                  Pill(
                    text: dl.text,
                    color: dl.color,
                    icon: dl.overdue ? Icons.warning_amber : Icons.event,
                  ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(desc),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Progress / অগ্রগতি', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text('${d.progress}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ProgressStrip(percent: d.progress, color: style.color),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // ---- My work (only if I am assigned) ----
      if (mine != null) _myWorkCard(context, mine),
      if (mine != null) const SizedBox(height: 16),

      // ---- People ----
      Text('People / দায়িত্বপ্রাপ্ত',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (d.assignees.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nobody assigned yet. Edit this sub-task to add people. / কাউকে দায়িত্ব দেওয়া হয়নি।'),
          ),
        ),
      for (final r in d.assignees) _personCard(context, r, canManage),
      const SizedBox(height: 20),

      // ---- Discussion for this sub-task ----
      Text('Discussion / আলোচনা',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Updates and questions about this sub-task. / এই উপ-কাজের আপডেট ও প্রশ্ন।',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      DiscussionSection(taskId: widget.taskId, subtaskId: widget.subtaskId),
    ];
  }

  Widget _myWorkCard(BuildContext context, Map<String, dynamic> mine) {
    final status = mine['status'] as String;
    final value = _slider ?? progressOf(mine).toDouble();
    final locked = status == 'under_review' || status == 'completed';

    return Card(
      color: AppColors.secondary.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.secondary.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My work / আমার কাজ',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                StateChip(state: status),
                const Spacer(),
                Text('${value.round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            if ((mine['review_note'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text('Reviewer note / মন্তব্য: ${mine['review_note']}',
                  style: const TextStyle(color: Color(0xFFEA580C))),
            ],
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 20,
              label: '${value.round()}%',
              onChanged: locked ? null : (v) => setState(() => _slider = v),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: locked
                      ? null
                      : () => _saveProgress(value.round(), status),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save progress / সংরক্ষণ'),
                ),
                FilledButton.icon(
                  onPressed: locked ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit / জমা দিন'),
                ),
              ],
            ),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  status == 'completed'
                      ? 'Approved. Thank you! / অনুমোদিত হয়েছে।'
                      : 'Waiting for review. / যাচাইয়ের অপেক্ষায়।',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _personCard(BuildContext context, Map<String, dynamic> r, bool canReview) {
    final name = nameOfRow(r);
    final status = r['status'] as String;
    final st = stateStyle(status);
    final pct = progressOf(r);
    final uid = r['user_id'] as String;
    final submission = (r['submission_note'] as String?) ?? '';
    final review = (r['review_note'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PersonAvatar(name: name, color: st.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  StateChip(state: status),
                ],
              ),
              const SizedBox(height: 10),
              ProgressStrip(percent: pct, color: st.color),
              const SizedBox(height: 4),
              Text('$pct%', style: const TextStyle(fontSize: 12)),
              if (submission.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Submitted / জমা: $submission'),
              ],
              if (review.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Review / মন্তব্য: $review',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ],
              if (canReview && status == 'under_review') ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _review(uid, approve: false),
                      icon: const Icon(Icons.replay),
                      label: const Text('Revision / সংশোধন'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _review(uid, approve: true),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve / অনুমোদন'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
