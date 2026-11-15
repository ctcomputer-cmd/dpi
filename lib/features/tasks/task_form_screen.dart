import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';
import 'task_shared.dart';

/// Create or edit the main task. People and deadlines are set per sub-task.
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
      final t = await taskSb.from('tasks').select().eq('id', widget.taskId!).single();
      _title.text = t['title'] as String;
      _description.text = (t['description'] as String?) ?? '';
      _category.text = (t['category'] as String?) ?? '';
      _departmentId = t['department_id'] as String?;
      _priority = t['priority'] as String;
      _status = t['status'] as String;
      _deadline = t['deadline'] == null
          ? null
          : DateTime.parse(t['deadline'] as String).toLocal();
    } catch (e) {
      _error = 'Could not load task. / কাজ লোড হয়নি। ${errorText(e)}';
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

    final uid = taskMe;
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
      if (_isEdit) {
        await taskSb.from('tasks').update(data).eq('id', widget.taskId!);
        await logTaskActivity(widget.taskId!, 'updated', {'status': _status, 'priority': _priority});
        ref.invalidate(taskListProvider);
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(taskDetailProvider(widget.taskId!));
        if (!mounted) return;
        if (context.canPop()) context.pop();
      } else {
        final row = await taskSb
            .from('tasks')
            .insert({...data, 'created_by': uid})
            .select('id')
            .single();
        final newId = row['id'] as String;
        await logTaskActivity(newId, 'created', {'status': _status, 'priority': _priority});
        ref.invalidate(taskListProvider);
        ref.invalidate(dashboardStatsProvider);
        if (!mounted) return;
        // Go straight to the new task so sub-tasks can be added.
        context.pushReplacement('/tasks/$newId');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: ${errorText(e)}');
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
      await taskSb.rpc('soft_delete_task', params: {'p_id': widget.taskId!});
      ref.invalidate(taskListProvider);
      ref.invalidate(dashboardStatsProvider);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/tasks');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentListProvider);

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
                  if (!_isEdit)
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'After saving, add sub-tasks and assign people with a deadline for each. / সেভ করার পর উপ-কাজ যোগ করে প্রত্যেকের জন্য মানুষ ও সময়সীমা দিন।',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
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
                    title: const Text('Overall deadline / শেষ তারিখ'),
                    subtitle: Text(_deadline == null
                        ? 'Not set / নির্ধারিত নয়'
                        : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'),
                    trailing: TextButton(
                        onPressed: _pickDeadline, child: const Text('Pick / বাছাই')),
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
