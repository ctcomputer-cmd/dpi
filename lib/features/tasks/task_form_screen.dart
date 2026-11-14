import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';

/// Create, edit and (soft) delete a task. Every write is checked by RLS.
class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId});

  /// null = create a new task.
  final String? taskId;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();

  String? _departmentId; // null = institute-wide
  String _priority = 'medium';
  String _status = 'not_started';
  DateTime? _deadline;
  final Set<String> _assignees = {};
  final Set<String> _originalAssignees = {};

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.taskId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sb = Supabase.instance.client;
      final t = await sb.from('tasks').select().eq('id', widget.taskId!).single();
      final a = await sb.from('task_assignees').select('user_id').eq('task_id', widget.taskId!);

      _title.text = t['title'] as String;
      _description.text = (t['description'] as String?) ?? '';
      _category.text = (t['category'] as String?) ?? '';
      _departmentId = t['department_id'] as String?;
      _priority = t['priority'] as String;
      _status = t['status'] as String;
      _deadline = t['deadline'] == null
          ? null
          : DateTime.parse(t['deadline'] as String).toLocal();
      for (final r in a as List) {
        final id = r['user_id'] as String;
        _assignees.add(id);
        _originalAssignees.add(id);
      }
    } catch (_) {
      _error = 'Could not load task. / কাজ লোড হয়নি।';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser!.id;
    final desc = _description.text.trim();
    final cat = _category.text.trim();

    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'description': desc.isEmpty ? null : desc,
      'category': cat.isEmpty ? null : cat,
      'department_id': _departmentId,
      'priority': _priority,
      'status': _status,
      'deadline': _deadline == null
          ? null
          : DateTime(_deadline!.year, _deadline!.month, _deadline!.day, 23, 59)
              .toUtc()
              .toIso8601String(),
      'updated_by': uid,
    };

    try {
      var taskId = widget.taskId ?? '';
      if (_isEdit) {
        await sb.from('tasks').update(data).eq('id', taskId);
      } else {
        final row = await sb
            .from('tasks')
            .insert({...data, 'created_by': uid})
            .select('id')
            .single();
        taskId = row['id'] as String;
      }

      // Sync assignees: each new teacher gets their own progress row.
      final toRemove = _originalAssignees.difference(_assignees).toList();
      final toAdd = _assignees.difference(_originalAssignees).toList();
      if (toRemove.isNotEmpty) {
        await sb
            .from('task_assignees')
            .delete()
            .eq('task_id', taskId)
            .inFilter('user_id', toRemove);
      }
      if (toAdd.isNotEmpty) {
        await sb.from('task_assignees').insert(toAdd
            .map((id) => {
                  'task_id': taskId,
                  'user_id': id,
                  'progress_percent': 0,
                  'status': 'not_started',
                })
            .toList());
      }

      await sb.from('task_activity_logs').insert({
        'task_id': taskId,
        'actor_id': uid,
        'action': _isEdit ? 'updated' : 'created',
        'details': {'status': _status, 'priority': _priority},
      });

      ref.invalidate(taskListProvider);
      ref.invalidate(dashboardStatsProvider);
      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      setState(() => _error = 'Could not save: ${e.message}');
    } catch (_) {
      setState(() => _error = 'Network error. / নেটওয়ার্ক সমস্যা।');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete task? / কাজ মুছবেন?'),
        content: const Text(
            'The task will be hidden from everyone. / কাজটি সবার কাছ থেকে লুকানো হবে।'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel / বাতিল')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete / মুছুন')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      // Soft delete: RLS allows managers to update; the row stays for audit.
      await Supabase.instance.client
          .from('tasks')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', widget.taskId!);
      ref.invalidate(taskListProvider);
      ref.invalidate(dashboardStatsProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Could not delete. / মুছে ফেলা যায়নি।');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentListProvider);
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit task / কাজ সম্পাদনা' : 'New task / নতুন কাজ'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete / মুছুন',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Title / শিরোনাম *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Title is required / শিরোনাম দিন'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description / বিবরণ'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _category,
                    decoration: const InputDecoration(labelText: 'Category / ধরন'),
                  ),
                  const SizedBox(height: 12),
                  departments.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Could not load departments.'),
                    data: (list) => DropdownButtonFormField<String?>(
                      value: _departmentId,
                      decoration: const InputDecoration(labelText: 'Department / বিভাগ'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Institute-wide / সকল বিভাগ')),
                        ...list.map((d) => DropdownMenuItem<String?>(
                              value: d.id,
                              child: Text(d.name),
                            )),
                      ],
                      onChanged: (v) => setState(() => _departmentId = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: const InputDecoration(labelText: 'Priority / অগ্রাধিকার'),
                    items: taskPriorities
                        .map((p) => DropdownMenuItem(
                            value: p, child: Text(prettyLabel(p).toUpperCase())))
                        .toList(),
                    onChanged: (v) => setState(() => _priority = v ?? _priority),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Status / অবস্থা'),
                    items: taskStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(prettyLabel(s))))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: const Text('Deadline / শেষ তারিখ'),
                    subtitle: Text(_deadline == null
                        ? 'Not set / নির্ধারিত নয়'
                        : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'),
                    trailing: TextButton(
                        onPressed: _pickDeadline, child: const Text('Pick / বাছাই')),
                  ),
                  const SizedBox(height: 12),
                  Text('Assign to / দায়িত্ব দিন',
                      style: Theme.of(context).textTheme.titleSmall),
                  staff.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Could not load staff.'),
                    data: (list) => Card(
                      child: Column(
                        children: [
                          for (final s in list.where((x) => x.isActive))
                            CheckboxListTile(
                              dense: true,
                              value: _assignees.contains(s.id),
                              title: Text(s.fullName),
                              subtitle: Text(s.designation ?? ''),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _assignees.add(s.id);
                                } else {
                                  _assignees.remove(s.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEdit ? 'Save changes / সংরক্ষণ' : 'Create task / তৈরি করুন'),
                  ),
                ],
              ),
            ),
    );
  }
}
