import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/providers/data_providers.dart';
import '../../shared/providers/directory_providers.dart';

const _assignableRoles = [
  'principal',
  'hod',
  'coordinator',
  'teacher',
  'lab_incharge',
  'event_coordinator',
];

/// Create a new staff account (via Edge Function) or edit an existing one.
class TeacherFormScreen extends ConsumerStatefulWidget {
  const TeacherFormScreen({super.key, this.userId});

  /// null = create a new staff member.
  final String? userId;

  @override
  ConsumerState<TeacherFormScreen> createState() => _TeacherFormScreenState();
}

class _TeacherFormScreenState extends ConsumerState<TeacherFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _employeeId = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  final _bio = TextEditingController();

  String? _departmentId;
  final Set<String> _roles = {};
  final Set<String> _originalRoles = {};
  String? _originalDepartmentId;
  bool _isActive = true;

  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _info;

  bool get _isEdit => widget.userId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    for (final c in [_fullName, _email, _employeeId, _designation, _phone, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sb = Supabase.instance.client;
      final p = await sb.from('profiles').select().eq('id', widget.userId!).single();
      final r = await sb.from('user_roles').select('role').eq('user_id', widget.userId!);
      final d = await sb
          .from('department_memberships')
          .select('department_id')
          .eq('user_id', widget.userId!);

      _fullName.text = (p['full_name'] as String?) ?? '';
      _email.text = (p['email'] as String?) ?? '';
      _employeeId.text = (p['employee_id'] as String?) ?? '';
      _designation.text = (p['designation'] as String?) ?? '';
      _phone.text = (p['phone'] as String?) ?? '';
      _bio.text = (p['bio'] as String?) ?? '';
      _isActive = (p['is_active'] as bool?) ?? true;

      for (final row in r as List) {
        final role = row['role'] as String;
        _roles.add(role);
        _originalRoles.add(role);
      }
      final deps = d as List;
      if (deps.isNotEmpty) {
        _departmentId = deps.first['department_id'] as String?;
        _originalDepartmentId = _departmentId;
      }
    } catch (_) {
      _error = 'Could not load profile. / প্রোফাইল লোড হয়নি।';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _opt(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });

    try {
      final sb = Supabase.instance.client;
      if (_isEdit) {
        await _updateExisting(sb);
      } else {
        await _createNew(sb);
      }
      ref.invalidate(staffListProvider);
      ref.invalidate(dashboardStatsProvider);
      if (mounted) context.pop();
    } on FunctionException catch (e) {
      setState(() => _error = 'Could not create account: ${e.details ?? e.reasonPhrase}');
    } on PostgrestException catch (e) {
      setState(() => _error = 'Could not save: ${e.message}');
    } catch (_) {
      setState(() => _error = 'Network error. / নেটওয়ার্ক সমস্যা।');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Account creation runs on the server, which needs the admin key.
  Future<void> _createNew(SupabaseClient sb) async {
    final res = await sb.functions.invoke('create-staff', body: {
      'email': _email.text.trim(),
      'full_name': _fullName.text.trim(),
      'employee_id': _opt(_employeeId.text),
      'designation': _opt(_designation.text),
      'phone': _opt(_phone.text),
      'bio': _opt(_bio.text),
      'department_id': _departmentId,
      'roles': _roles.toList(),
    });
    if (res.status != 200) {
      throw FunctionException(status: res.status, details: res.data);
    }
  }

  Future<void> _updateExisting(SupabaseClient sb) async {
    final uid = sb.auth.currentUser!.id;
    await sb.from('profiles').update({
      'full_name': _fullName.text.trim(),
      'employee_id': _opt(_employeeId.text),
      'designation': _opt(_designation.text),
      'phone': _opt(_phone.text),
      'bio': _opt(_bio.text),
      'is_active': _isActive,
      'updated_by': uid,
    }).eq('id', widget.userId!);

    // Roles: only super_admin may change them (enforced by RLS).
    final removeRoles = _originalRoles.difference(_roles).toList();
    final addRoles = _roles.difference(_originalRoles).toList();
    if (removeRoles.isNotEmpty) {
      await sb
          .from('user_roles')
          .delete()
          .eq('user_id', widget.userId!)
          .inFilter('role', removeRoles);
    }
    if (addRoles.isNotEmpty) {
      await sb.from('user_roles').insert(
          addRoles.map((r) => {'user_id': widget.userId, 'role': r}).toList());
    }

    // Department: replace the single membership when it changes.
    if (_departmentId != _originalDepartmentId) {
      await sb.from('department_memberships').delete().eq('user_id', widget.userId!);
      if (_departmentId != null) {
        await sb
            .from('department_memberships')
            .insert({'user_id': widget.userId, 'department_id': _departmentId});
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      setState(() => _info = 'Reset link sent to $email. / রিসেট লিংক পাঠানো হয়েছে।');
    } catch (_) {
      setState(() => _error = 'Could not send reset link. / লিংক পাঠানো যায়নি।');
    }
  }

  Future<void> _toggleDelete() async {
    // "Delete" for staff means deactivate: history (tasks, meetings) is kept.
    setState(() => _isActive = !_isActive);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit staff / কর্মী সম্পাদনা' : 'Add staff / নতুন কর্মী'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _fullName,
                    decoration: const InputDecoration(labelText: 'Full name / পূর্ণ নাম *'),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Enter full name / পূর্ণ নাম লিখুন'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    enabled: !_isEdit,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email / ইমেইল *',
                      helperText: _isEdit
                          ? 'Email cannot be changed here / ইমেইল এখানে বদলানো যায় না'
                          : 'Login link will be emailed / লগইন লিংক ইমেইল হবে',
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email / সঠিক ইমেইল লিখুন'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _employeeId,
                    decoration: const InputDecoration(labelText: 'Employee ID / আইডি'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _designation,
                    decoration: const InputDecoration(labelText: 'Designation / পদবি'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone / ফোন'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Short bio / সংক্ষিপ্ত পরিচিতি'),
                  ),
                  const SizedBox(height: 12),
                  departments.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Could not load departments.'),
                    data: (list) => DropdownButtonFormField<String?>(
                      value: _departmentId,
                      decoration: const InputDecoration(labelText: 'Department / বিভাগ'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('None / নেই')),
                        ...list.map((d) =>
                            DropdownMenuItem<String?>(value: d.id, child: Text(d.name))),
                      ],
                      onChanged: (v) => setState(() => _departmentId = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Roles / ভূমিকা', style: Theme.of(context).textTheme.titleSmall),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in _assignableRoles)
                        FilterChip(
                          label: Text(r.replaceAll('_', ' ')),
                          selected: _roles.contains(r),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _roles.add(r);
                            } else {
                              _roles.remove(r);
                            }
                          }),
                        ),
                    ],
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active account / সক্রিয় অ্যাকাউন্ট'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: const TextStyle(color: Colors.green)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEdit ? 'Save changes / সংরক্ষণ' : 'Create account / তৈরি করুন'),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _sendPasswordReset,
                      icon: const Icon(Icons.lock_reset),
                      label: const Text('Send password reset / পাসওয়ার্ড রিসেট'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving ? null : _toggleDelete,
                      child: Text(_isActive
                          ? 'Deactivate account / নিষ্ক্রিয় করুন'
                          : 'Reactivate account / সক্রিয় করুন'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
