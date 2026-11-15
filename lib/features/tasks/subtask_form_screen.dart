import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';
import 'task_shared.dart';

/// Create or edit a sub-task: title, description, deadline and the people on it.
class SubtaskFormScreen extends ConsumerStatefulWidget {
  const SubtaskFormScreen({super.key, required this.taskId, this.subtaskId});

  final String taskId;

  /// null = new sub-task.
  final String? subtaskId;

  @override
  ConsumerState<SubtaskFormScreen> createState() => _SubtaskFormScreenState();
}

class _SubtaskFormScreenState extends ConsumerState<SubtaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _search = TextEditingController();

  DateTime? _deadline;
  final Set<String> _selected = {};
  final Set<String> _original = {};
  String _query = '';

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.subtaskId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await taskSb
          .from('task_subtasks')
          .select()
          .eq('id', widget.subtaskId!)
          .single();
      final a = await taskSb
          .from('subtask_assignees')
          .select('user_id')
          .eq('subtask_id', widget.subtaskId!);

      _title.text = s['title'] as String;
      _desc.text = (s['description'] as String?) ?? '';
      _deadline = s['deadline'] == null
          ? null
          : DateTime.parse(s['deadline'] as String).toLocal();
      for (final r in asRows(a)) {
        final id = r['user_id'] as String;
        _selected.add(id);
        _original.add(id);
      }
    } catch (e) {
      _error = 'Could not load. / লোড হয়নি। ${errorText(e)}';
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

    final desc = _desc.text.trim();
    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'description': desc.isEmpty ? null : desc,
      'deadline': _deadline == null
          ? null
          : DateTime(_deadline!.year, _deadline!.month, _deadline!.day, 23, 59)
              .toUtc()
              .toIso8601String(),
    };

    try {
      String subId;
      if (_isEdit) {
        subId = widget.subtaskId!;
        await taskSb.from('task_subtasks').update(data).eq('id', subId);
      } else {
        final row = await taskSb
            .from('task_subtasks')
            .insert({...data, 'task_id': widget.taskId, 'created_by': taskMe})
            .select('id')
            .single();
        subId = row['id'] as String;
      }

      // Sync people: removed ones are deleted, new ones start at 0%.
      final toRemove = _original.difference(_selected).toList();
      final toAdd = _selected.difference(_original).toList();
      if (toRemove.isNotEmpty) {
        await taskSb
            .from('subtask_assignees')
            .delete()
            .eq('subtask_id', subId)
            .inFilter('user_id', toRemove);
      }
      if (toAdd.isNotEmpty) {
        await taskSb.from('subtask_assignees').insert([
          for (final id in toAdd)
            {
              'subtask_id': subId,
              'user_id': id,
              'progress_percent': 0,
              'status': 'not_started',
            },
        ]);
      }

      await logTaskActivity(
        widget.taskId,
        _isEdit ? 'subtask_updated' : 'subtask_created',
        {'subtask': _title.text.trim(), 'people': _selected.length},
      );

      ref.invalidate(taskDetailProvider(widget.taskId));
      ref.invalidate(taskListProvider);
      if (!mounted) return;
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _assigneePicker() {
    final staff = ref.watch(staffListProvider);
    final list = staff.valueOrNull ?? const <StaffMember>[];
    final byId = {for (final s in list) s.id: s};
    final active = list.where((s) => s.isActive).toList();
    final filtered = active.where((s) {
      if (_query.isEmpty) return true;
      return [s.fullName, s.designation, s.employeeId]
          .whereType<String>()
          .any((x) => x.toLowerCase().contains(_query));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assign people / দায়িত্ব দিন',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('${_selected.length} selected / জন নির্বাচিত',
            style: const TextStyle(fontSize: 12)),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in _selected)
                InputChip(
                  label: Text(byId[id]?.fullName ?? 'Unknown'),
                  onDeleted: () => setState(() => _selected.remove(id)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Type a name to search / নাম লিখে খুঁজুন',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () =>
                  setState(() => _selected.addAll(active.map((s) => s.id))),
              icon: const Icon(Icons.group_add),
              label: const Text('Select all / সবাইকে'),
            ),
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: const Text('Clear / মুছুন'),
            ),
          ],
        ),
        if (staff.isLoading) const LinearProgressIndicator(),
        Card(
          child: Column(
            children: [
              for (final s in filtered)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(s.id),
                  title: Text(s.fullName),
                  subtitle: Text(s.designation ?? ''),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(s.id);
                    } else {
                      _selected.remove(s.id);
                    }
                  }),
                ),
              if (!staff.isLoading && filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No matching people. / মিল পাওয়া যায়নি।'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit sub-task / উপ-কাজ সম্পাদনা' : 'New sub-task / নতুন উপ-কাজ'),
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
                    decoration: const InputDecoration(labelText: 'Sub-task title / উপ-কাজের নাম *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Title is required / নাম দিন'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _desc,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Details / বিবরণ'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: const Text('Deadline / শেষ তারিখ'),
                    subtitle: Text(_deadline == null
                        ? 'Not set / নির্ধারিত নয়'
                        : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'),
                    trailing: Wrap(
                      children: [
                        if (_deadline != null)
                          IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _deadline = null),
                          ),
                        TextButton(onPressed: _pickDeadline, child: const Text('Pick / বাছাই')),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  _assigneePicker(),
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
                        : Text(_isEdit ? 'Save changes / সংরক্ষণ' : 'Add sub-task / যোগ করুন'),
                  ),
                ],
              ),
            ),
    );
  }
}
