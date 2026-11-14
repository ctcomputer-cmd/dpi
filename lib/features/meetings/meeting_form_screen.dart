import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/providers/directory_providers.dart';
import '../../shared/providers/meeting_providers.dart';

const _meetingStatuses = ['scheduled', 'ongoing', 'completed', 'cancelled'];

/// Create, edit and (soft) delete a meeting with participants.
class MeetingFormScreen extends ConsumerStatefulWidget {
  const MeetingFormScreen({super.key, this.meetingId});

  /// null = create a new meeting.
  final String? meetingId;

  @override
  ConsumerState<MeetingFormScreen> createState() => _MeetingFormScreenState();
}

class _MeetingFormScreenState extends ConsumerState<MeetingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _agenda = TextEditingController();
  final _description = TextEditingController();
  final _meetLink = TextEditingController();
  final _notes = TextEditingController();
  final _decisions = TextEditingController();

  String? _departmentId; // null = institute-wide
  String _status = 'scheduled';
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 11, minute: 0);
  final Set<String> _participants = {};
  final Set<String> _originalParticipants = {};

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.meetingId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _agenda, _description, _meetLink, _notes, _decisions]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _combine(DateTime d, TimeOfDay t) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sb = Supabase.instance.client;
      final m = await sb.from('meetings').select().eq('id', widget.meetingId!).single();
      final p = await sb
          .from('meeting_participants')
          .select('user_id')
          .eq('meeting_id', widget.meetingId!);

      _title.text = m['title'] as String;
      _agenda.text = (m['agenda'] as String?) ?? '';
      _description.text = (m['description'] as String?) ?? '';
      _meetLink.text = (m['meet_link'] as String?) ?? '';
      _notes.text = (m['notes'] as String?) ?? '';
      _decisions.text = (m['decisions'] as String?) ?? '';
      _departmentId = m['department_id'] as String?;
      _status = m['status'] as String;
      final s = DateTime.parse(m['starts_at'] as String).toLocal();
      final e = DateTime.parse(m['ends_at'] as String).toLocal();
      _date = DateTime(s.year, s.month, s.day);
      _start = TimeOfDay.fromDateTime(s);
      _end = TimeOfDay.fromDateTime(e);
      for (final r in p as List) {
        final id = r['user_id'] as String;
        _participants.add(id);
        _originalParticipants.add(id);
      }
    } catch (_) {
      _error = 'Could not load meeting. / সভা লোড হয়নি।';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final startsAt = _combine(_date, _start);
    final endsAt = _combine(_date, _end);
    if (!endsAt.isAfter(startsAt)) {
      setState(() => _error = 'End time must be after start time. / শেষ সময় শুরুর পরে হতে হবে।');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser!.id;
    String? orNull(String v) => v.trim().isEmpty ? null : v.trim();

    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'agenda': orNull(_agenda.text),
      'description': orNull(_description.text),
      'department_id': _departmentId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'meet_link': orNull(_meetLink.text), // entered manually (fallback)
      'status': _status,
      'notes': orNull(_notes.text),
      'decisions': orNull(_decisions.text),
    };

    try {
      var meetingId = widget.meetingId ?? '';
      if (_isEdit) {
        await sb.from('meetings').update(data).eq('id', meetingId);
      } else {
        final row = await sb
            .from('meetings')
            .insert({...data, 'organizer_id': uid})
            .select('id')
            .single();
        meetingId = row['id'] as String;
      }

      final toRemove = _originalParticipants.difference(_participants).toList();
      final toAdd = _participants.difference(_originalParticipants).toList();
      if (toRemove.isNotEmpty) {
        await sb
            .from('meeting_participants')
            .delete()
            .eq('meeting_id', meetingId)
            .inFilter('user_id', toRemove);
      }
      if (toAdd.isNotEmpty) {
        await sb.from('meeting_participants').insert(toAdd
            .map((id) => {'meeting_id': meetingId, 'user_id': id})
            .toList());
      }

      ref.invalidate(upcomingMeetingsProvider);
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
        title: const Text('Delete meeting? / সভা মুছবেন?'),
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
      await Supabase.instance.client
          .rpc('soft_delete_meeting', params: {'p_id': widget.meetingId!});
      ref.invalidate(upcomingMeetingsProvider);
      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      setState(() => _error = 'Could not delete: ${e.message}');
    } catch (_) {
      setState(() => _error = 'Could not delete. / মুছে ফেলা যায়নি।');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentListProvider);
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit meeting / সভা সম্পাদনা' : 'New meeting / নতুন সভা'),
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
                    decoration: const InputDecoration(labelText: 'Meeting title / সভার শিরোনাম *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Title is required / শিরোনাম দিন' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _agenda,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Agenda / আলোচ্যসূচি'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description / বিবরণ'),
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
                        ...list.map((d) =>
                            DropdownMenuItem<String?>(value: d.id, child: Text(d.name))),
                      ],
                      onChanged: (v) => setState(() => _departmentId = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Date / তারিখ'),
                    subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
                    trailing: TextButton(onPressed: _pickDate, child: const Text('Pick')),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Start / শুরু'),
                    subtitle: Text(_start.format(context)),
                    trailing: TextButton(
                        onPressed: () => _pickTime(true), child: const Text('Pick')),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('End / শেষ'),
                    subtitle: Text(_end.format(context)),
                    trailing: TextButton(
                        onPressed: () => _pickTime(false), child: const Text('Pick')),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _meetLink,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Google Meet link / মিট লিংক (ঐচ্ছিক)',
                      hintText: 'https://meet.google.com/...',
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty || t.startsWith('https://')) return null;
                      return 'Link must start with https:// / লিংক https:// দিয়ে শুরু হতে হবে';
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Status / অবস্থা'),
                    items: _meetingStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 16),
                  Text('Participants / অংশগ্রহণকারী',
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
                              value: _participants.contains(s.id),
                              title: Text(s.fullName),
                              subtitle: Text(s.designation ?? ''),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _participants.add(s.id);
                                } else {
                                  _participants.remove(s.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Meeting notes / সভার নোট'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _decisions,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Decisions / সিদ্ধান্ত'),
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
                        : Text(_isEdit ? 'Save changes / সংরক্ষণ' : 'Create meeting / তৈরি করুন'),
                  ),
                ],
              ),
            ),
    );
  }
}
