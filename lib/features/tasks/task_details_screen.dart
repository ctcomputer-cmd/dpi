import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';

final _sb = Supabase.instance.client;

List<Map<String, dynamic>> _rows(dynamic v) => List<Map<String, dynamic>>.from(v as List);

class TaskDetail {
  const TaskDetail({
    required this.task,
    required this.assignees,
    required this.comments,
    required this.attachments,
    required this.activity,
  });

  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> assignees;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> attachments;
  final List<Map<String, dynamic>> activity;
}

final taskDetailProvider =
    FutureProvider.autoDispose.family<TaskDetail, String>((ref, id) async {
  final t = await _sb.from('tasks').select().eq('id', id).single();
  final a = await _sb
      .from('task_assignees')
      .select('user_id, progress_percent, status, submission_note, submitted_at, review_note, profiles(full_name)')
      .eq('task_id', id);
  final c = await _sb
      .from('task_comments')
      .select('body, author_id, created_at, profiles(full_name)')
      .eq('task_id', id)
      .order('created_at');
  final f = await _sb
      .from('task_attachments')
      .select('id, file_name, storage_path, mime_type, created_at')
      .eq('task_id', id)
      .order('created_at');
  final l = await _sb
      .from('task_activity_logs')
      .select('action, details, created_at, profiles(full_name)')
      .eq('task_id', id)
      .order('created_at', ascending: false)
      .limit(50);
  return TaskDetail(
    task: Map<String, dynamic>.from(t),
    assignees: _rows(a),
    comments: _rows(c),
    attachments: _rows(f),
    activity: _rows(l),
  );
});

const _maxFileBytes = 10 * 1024 * 1024;
const _mimeByExt = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

String _statusLabel(String s) => prettyLabel(s);

class TaskDetailsScreen extends ConsumerStatefulWidget {
  const TaskDetailsScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends ConsumerState<TaskDetailsScreen> {
  final _comment = TextEditingController();
  bool _busy = false;
  double? _myProgress;

  String get _me => _sb.auth.currentUser!.id;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(taskDetailProvider(widget.taskId));

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Runs a write, shows any error, then reloads the screen.
  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (ok != null) _toast(ok);
    } on PostgrestException catch (e) {
      _toast('Failed: ${e.message}');
    } on StorageException catch (e) {
      _toast('Upload failed: ${e.message}');
    } catch (_) {
      _toast('Network error. / নেটওয়ার্ক সমস্যা।');
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _log(String action, [Map<String, dynamic>? details]) async {
    await _sb.from('task_activity_logs').insert({
      'task_id': widget.taskId,
      'actor_id': _me,
      'action': action,
      'details': details ?? {},
    });
  }

  Future<void> _saveProgress(int value, String currentStatus) => _run(() async {
        final update = <String, dynamic>{'progress_percent': value};
        if (currentStatus == 'not_started' && value > 0) update['status'] = 'in_progress';
        await _sb
            .from('task_assignees')
            .update(update)
            .eq('task_id', widget.taskId)
            .eq('user_id', _me);
        await _log('progress_updated', {'progress': value});
      }, ok: 'Progress saved / অগ্রগতি সংরক্ষিত');

  Future<String?> _askText(String title, {bool required = false}) async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Note / নোট'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (required && c.text.trim().isEmpty) return;
              Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    c.dispose();
    return result;
  }

  Future<void> _submitForReview() async {
    final note = await _askText('Submit completed work / কাজ জমা দিন');
    if (note == null) return;
    await _run(() async {
      await _sb.from('task_assignees').update({
        'status': 'under_review',
        'progress_percent': 100,
        'submission_note': note.isEmpty ? null : note,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('task_id', widget.taskId).eq('user_id', _me);
      await _log('submitted_for_review');
    }, ok: 'Submitted / জমা দেওয়া হয়েছে');
  }

  Future<void> _review(String userId, {required bool approve}) async {
    final note = await _askText(
        approve ? 'Approve / অনুমোদন' : 'Request revision / সংশোধন চান',
        required: !approve);
    if (note == null) return;
    await _run(() async {
      await _sb.from('task_assignees').update({
        'status': approve ? 'completed' : 'revision_required',
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': _me,
        'review_note': note.isEmpty ? null : note,
      }).eq('task_id', widget.taskId).eq('user_id', userId);
      await _log(approve ? 'approved' : 'revision_requested', {'user_id': userId});

      // If everyone has been approved, close the whole task.
      final rows = await _sb
          .from('task_assignees')
          .select('status')
          .eq('task_id', widget.taskId);
      final all = _rows(rows);
      if (all.isNotEmpty && all.every((r) => r['status'] == 'completed')) {
        await _sb.from('tasks').update({'status': 'completed', 'updated_by': _me})
            .eq('id', widget.taskId);
      }
    }, ok: approve ? 'Approved / অনুমোদিত' : 'Revision requested / সংশোধনের অনুরোধ');
  }

  Future<void> _postComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    await _run(() async {
      await _sb.from('task_comments').insert({
        'task_id': widget.taskId,
        'author_id': _me,
        'body': body,
      });
      _comment.clear();
    });
  }

  Future<void> _uploadFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast('Could not read file. / ফাইল পড়া যায়নি।');
      return;
    }
    if (bytes.length > _maxFileBytes) {
      _toast('File is larger than 10 MB. / ফাইল ১০ MB-এর বেশি।');
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    final mime = _mimeByExt[ext];
    if (mime == null) {
      _toast('Only PDF, PNG, JPG, DOCX, XLSX allowed. / শুধু PDF, ছবি, DOCX, XLSX।');
      return;
    }
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${widget.taskId}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _run(() async {
      await _sb.storage.from('task-files').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: mime),
          );
      await _sb.from('task_attachments').insert({
        'task_id': widget.taskId,
        'uploaded_by': _me,
        'file_name': file.name,
        'storage_path': path,
        'mime_type': mime,
        'size_bytes': bytes.length,
      });
      await _log('file_uploaded', {'file': file.name});
    }, ok: 'File uploaded / ফাইল যুক্ত হয়েছে');
  }

  Future<void> _openFile(String path) async {
    try {
      final url = await _sb.storage.from('task-files').createSignedUrl(path, 300);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _toast('Could not open file. / ফাইল খোলা যায়নি।');
    }
  }

  Future<void> _deleteTask() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete task? / কাজ মুছবেন?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _sb.rpc('soft_delete_task', params: {'p_id': widget.taskId});
    });
    ref.invalidate(taskListProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(taskDetailProvider(widget.taskId));
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <String>[];
    final isAdmin = roles.contains('super_admin') || roles.contains('principal');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task / কাজ'),
        actions: [
          IconButton(
            tooltip: 'Edit / সম্পাদনা',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await context.push('/tasks/${widget.taskId}/edit');
              _refresh();
            },
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load. / লোড হয়নি।'),
                const SizedBox(height: 8),
                Text('$e', style: const TextStyle(fontSize: 12, color: Colors.black54),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _refresh, child: const Text('Retry / আবার')),
              ],
            ),
          ),
        ),
        data: (d) {
          final t = d.task;
          final created = t['created_by'] as String?;
          final canReview = isAdmin || created == _me;
          final mine = d.assignees.where((a) => a['user_id'] == _me).toList();
          final myRow = mine.isEmpty ? null : mine.first;
          final overall = d.assignees.isEmpty
              ? 0
              : d.assignees.fold<int>(0, (s, a) => s + (a['progress_percent'] as int)) ~/
                  d.assignees.length;
          final deadline = t['deadline'] == null
              ? null
              : DateTime.parse(t['deadline'] as String).toLocal();

          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t['title'] as String,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text([
                  _statusLabel(t['status'] as String),
                  prettyLabel(t['priority'] as String).toUpperCase(),
                  if (deadline != null) 'Due ${DateFormat('dd MMM yyyy').format(deadline)}',
                ].join(' • ')),
                if ((t['description'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 10),
                  Text(t['description'] as String),
                ],
                const SizedBox(height: 16),
                _section('Overall progress / সামগ্রিক অগ্রগতি'),
                LinearProgressIndicator(value: overall / 100, minHeight: 8),
                Text('$overall%'),
                const SizedBox(height: 12),
                _section('Assigned teachers / দায়িত্বপ্রাপ্ত'),
                if (d.assignees.isEmpty) const Text('No one assigned / কাউকে দায়িত্ব দেওয়া হয়নি'),
                for (final a in d.assignees)
                  Card(
                    child: ListTile(
                      title: Text(((a['profiles'] as Map?)?['full_name'] as String?) ?? 'Unknown'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_statusLabel(a['status'] as String)} • ${a['progress_percent']}%'),
                          LinearProgressIndicator(value: (a['progress_percent'] as int) / 100),
                          if ((a['submission_note'] as String?)?.isNotEmpty ?? false)
                            Text('Note: ${a['submission_note']}'),
                          if ((a['review_note'] as String?)?.isNotEmpty ?? false)
                            Text('Review: ${a['review_note']}'),
                        ],
                      ),
                    ),
                  ),
                if (myRow != null) ...[
                  const SizedBox(height: 12),
                  _section('My progress / আমার অগ্রগতি'),
                  Slider(
                    value: _myProgress ?? (myRow['progress_percent'] as int).toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${(_myProgress ?? (myRow['progress_percent'] as int).toDouble()).round()}%',
                    onChanged: (v) => setState(() => _myProgress = v),
                  ),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _saveProgress(
                          (_myProgress ?? (myRow['progress_percent'] as int).toDouble()).round(),
                          myRow['status'] as String,
                        ),
                        child: const Text('Save progress'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: myRow['status'] == 'under_review' || myRow['status'] == 'completed'
                            ? null
                            : _submitForReview,
                        child: const Text('Submit'),
                      ),
                    ),
                  ]),
                ],
                if (canReview) ...[
                  const SizedBox(height: 12),
                  _section('Review / পর্যালোচনা'),
                  for (final a in d.assignees.where((a) => a['status'] == 'under_review'))
                    Card(
                      child: ListTile(
                        title: Text(((a['profiles'] as Map?)?['full_name'] as String?) ?? ''),
                        subtitle: Text('Submitted / জমা: ${a['submission_note'] ?? '-'}'),
                        trailing: Wrap(spacing: 4, children: [
                          IconButton(
                            tooltip: 'Approve',
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => _review(a['user_id'] as String, approve: true),
                          ),
                          IconButton(
                            tooltip: 'Revision',
                            icon: const Icon(Icons.replay, color: Colors.orange),
                            onPressed: () => _review(a['user_id'] as String, approve: false),
                          ),
                        ]),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _section('Files / ফাইল')),
                  TextButton.icon(
                    onPressed: _busy ? null : _uploadFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Add'),
                  ),
                ]),
                if (d.attachments.isEmpty) const Text('No files / কোনো ফাইল নেই'),
                for (final f in d.attachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(f['file_name'] as String),
                    trailing: const Icon(Icons.download),
                    onTap: () => _openFile(f['storage_path'] as String),
                  ),
                const SizedBox(height: 12),
                _section('Comments / মন্তব্য'),
                for (final c in d.comments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(((c['profiles'] as Map?)?['full_name'] as String?) ?? ''),
                    subtitle: Text(c['body'] as String),
                  ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      decoration: const InputDecoration(hintText: 'Write a comment / মন্তব্য লিখুন'),
                    ),
                  ),
                  IconButton(onPressed: _postComment, icon: const Icon(Icons.send)),
                ]),
                const SizedBox(height: 12),
                _section('Activity / কার্যক্রম'),
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
                if (isAdmin || created == _me) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _deleteTask,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete task / কাজ মুছুন'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );
}
