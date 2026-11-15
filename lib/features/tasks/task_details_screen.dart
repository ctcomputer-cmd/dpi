import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';
import 'task_shared.dart';

const _maxFileBytes = 10 * 1024 * 1024;
const _mimeByExt = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/// Main task overview: summary, sub-task list, files, discussion and activity.
class TaskDetailsScreen extends ConsumerStatefulWidget {
  const TaskDetailsScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends ConsumerState<TaskDetailsScreen> {
  bool _busy = false;

  void _refresh() => ref.invalidate(taskDetailProvider(widget.taskId));

  Future<void> _uploadFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      showMsg(context, 'Could not read file. / ফাইল পড়া যায়নি।');
      return;
    }
    if (bytes.length > _maxFileBytes) {
      showMsg(context, 'File is larger than 10 MB. / ফাইল ১০ MB-এর বেশি।');
      return;
    }
    final mime = _mimeByExt[(file.extension ?? '').toLowerCase()];
    if (mime == null) {
      showMsg(context, 'Only PDF, PNG, JPG, DOCX, XLSX allowed. / শুধু PDF, ছবি, DOCX, XLSX।');
      return;
    }
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${widget.taskId}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    setState(() => _busy = true);
    try {
      await taskSb.storage.from('task-files').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: mime),
          );
      await taskSb.from('task_attachments').insert({
        'task_id': widget.taskId,
        'uploaded_by': taskMe,
        'file_name': file.name,
        'storage_path': path,
        'mime_type': mime,
        'size_bytes': bytes.length,
      });
      await logTaskActivity(widget.taskId, 'file_uploaded', {'file': file.name});
      if (mounted) showMsg(context, 'File uploaded / ফাইল যুক্ত হয়েছে');
    } catch (e) {
      if (mounted) showMsg(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) _refresh();
    }
  }

  Future<void> _openFile(String path) async {
    try {
      final url = await taskSb.storage.from('task-files').createSignedUrl(path, 300);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showMsg(context, 'Could not open file. / ফাইল খোলা যায়নি।');
    }
  }

  Future<void> _deleteTask() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete task? / কাজ মুছবেন?'),
        content: const Text('Everyone will lose access to it. / সবার কাছ থেকে লুকানো হবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await taskSb.rpc('soft_delete_task', params: {'p_id': widget.taskId});
      ref.invalidate(taskListProvider);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/tasks');
      }
    } catch (e) {
      if (mounted) showMsg(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <String>[];
    final loaded = async.valueOrNull;
    final canManage =
        loaded != null && canManageTaskUi(loaded.task['created_by'] as String, roles);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task / কাজ'),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Edit task / সম্পাদনা',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push('/tasks/${widget.taskId}/edit');
                _refresh();
              },
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_task),
              label: const Text('Sub-task / উপ-কাজ'),
              onPressed: () async {
                await context.push('/tasks/${widget.taskId}/subtasks/new');
                _refresh();
              },
            )
          : null,
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
                Text('$e',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _refresh, child: const Text('Retry / আবার')),
              ],
            ),
          ),
        ),
        data: (d) => AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: _content(context, d, canManage),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, TaskDetail d, bool canManage) {
    final theme = Theme.of(context);
    final t = d.task;
    final status = t['status'] as String;
    final priority = t['priority'] as String;
    final done = status == 'completed';
    final dl = deadlineInfo(t['deadline'] as String?, done: done);
    final desc = (t['description'] as String?) ?? '';
    final progress = d.overallProgress;

    return [
      // ---- Summary ----
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t['title'] as String,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StateChip(state: status),
                  Pill(
                    text: prettyLabel(priority).toUpperCase(),
                    color: priorityColor(priority),
                    icon: Icons.flag,
                  ),
                  Pill(
                    text: dl.text,
                    color: dl.color,
                    icon: dl.overdue ? Icons.warning_amber : Icons.event,
                  ),
                  Pill(
                    text: 'By ${d.creatorName.isEmpty ? '-' : d.creatorName}',
                    color: Colors.blueGrey,
                    icon: Icons.person_outline,
                  ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(desc),
              ],
              if (canManage) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Overall progress / সামগ্রিক অগ্রগতি',
                      style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text('$progress%',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ProgressStrip(percent: progress, color: AppColors.secondary),
              const SizedBox(height: 6),
              Text(
                '${d.completedSubtasks} of ${d.subtasks.length} sub-tasks done / '
                '${d.subtasks.length} টির মধ্যে ${d.completedSubtasks} টি সম্পন্ন',
                style: const TextStyle(fontSize: 12),
              ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),

      // ---- Sub-tasks ----
      Row(
        children: [
          Expanded(
            child: Text('Sub-tasks / উপ-কাজ',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text('${d.subtasks.length}'),
        ],
      ),
      const SizedBox(height: 8),
      if (d.subtasks.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.checklist, size: 40, color: Colors.blueGrey),
                const SizedBox(height: 8),
                const Text('No sub-tasks yet / এখনো উপ-কাজ নেই',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  canManage
                      ? 'Add a sub-task, then pick the people and a deadline for it. / উপ-কাজ যোগ করে মানুষ ও সময়সীমা বাছাই করুন।'
                      : 'Sub-tasks will appear here. / উপ-কাজগুলো এখানে দেখা যাবে।',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        )
      else
        for (final s in d.subtasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SubtaskCard(
              subtask: s,
              onTap: () async {
                await context.push('/tasks/${widget.taskId}/subtasks/${s['id']}');
                _refresh();
              },
            ),
          ),
      const SizedBox(height: 20),

      // ---- Files ----
      Row(
        children: [
          Expanded(
            child: Text('Files / ফাইল',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: _uploadFile,
            icon: const Icon(Icons.attach_file),
            label: const Text('Add / যোগ'),
          ),
        ],
      ),
      if (d.attachments.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('No files / কোনো ফাইল নেই'),
        ),
      for (final f in d.attachments)
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(f['file_name'] as String),
            trailing: const Icon(Icons.download),
            onTap: () => _openFile(f['storage_path'] as String),
          ),
        ),
      const SizedBox(height: 20),

      // ---- General discussion ----
      Text('Discussion / আলোচনা',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Whole-task messages. For a sub-task, open it. / পুরো কাজ নিয়ে কথা। উপ-কাজের আলোচনা উপ-কাজ খুললে পাবেন।',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      DiscussionSection(taskId: widget.taskId),
      const SizedBox(height: 12),

      // ---- Activity ----
      if (canManage)
        ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Activity / কার্যক্রম',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        children: [
          if (d.activity.isEmpty)
            const ListTile(title: Text('No activity yet / এখনো কিছু নেই')),
          for (final a in d.activity)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(a['action'] as String),
              subtitle: Text(
                '${((a['profiles'] as Map?)?['full_name'] as String?) ?? ''} • '
                '${DateFormat('dd MMM, hh:mm a').format(DateTime.parse(a['created_at'] as String).toLocal())}',
              ),
            ),
        ],
      ),

      if (canManage) ...[
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _deleteTask,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete task / কাজ মুছুন'),
        ),
      ],
    ];
  }
}

class _SubtaskCard extends StatelessWidget {
  const _SubtaskCard({required this.subtask, required this.onTap});

  final Map<String, dynamic> subtask;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rows = TaskDetail.assigneesOf(subtask);
    final state = subtaskState(rows);
    final style = stateStyle(state);
    final pct = avgProgress(rows);
    final dl = deadlineInfo(subtask['deadline'] as String?, done: state == 'completed');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: style.color.withOpacity(0.5), width: 1.2),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subtask['title'] as String,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  if (rows.isEmpty)
                    const Text('No one assigned / কেউ নেই', style: TextStyle(fontSize: 12)),
                  for (final r in rows.take(6))
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: PersonAvatar(
                        name: nameOfRow(r),
                        color: stateStyle(r['status'] as String).color,
                        radius: 14,
                      ),
                    ),
                  if (rows.length > 6) Text('+${rows.length - 6}'),
                ],
              ),
              const SizedBox(height: 10),
              ProgressStrip(percent: pct, color: style.color),
              const SizedBox(height: 4),
              Text('$pct% • ${rows.length} people / জন',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
