import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/providers/directory_providers.dart';

/// Read-only view of the signed-in user's own profile.
/// Only a super admin can change it (ask one to edit).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<String> _roles = const [];
  List<String> _depts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final sb = Supabase.instance.client;
    try {
      final row = await sb
          .from('profiles')
          .select('full_name, employee_id, designation, email, phone, bio, joining_date')
          .eq('id', user.id)
          .maybeSingle();
      final roleRows = await sb.from('user_roles').select('role').eq('user_id', user.id);
      final deptRows = await sb
          .from('department_memberships')
          .select('departments(name)')
          .eq('user_id', user.id);
      if (!mounted) return;
      setState(() {
        _profile = row;
        _roles = [for (final r in roleRows as List) r['role'] as String];
        _depts = [
          for (final r in deptRows as List)
            if ((r['departments'] as Map?)?['name'] != null)
              (r['departments'] as Map)['name'] as String,
        ];
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load profile. / প্রোফাইল লোড হয়নি।');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    // Ends the session on this device; the router sends the user to /login.
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final name = (p?['full_name'] as String?) ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile / প্রোফাইল')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                if (p != null) ...[
                  Center(
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.secondary,
                      child: Text(
                        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 30),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (p['designation'] != null)
                    Center(
                      child: Text(p['designation'] as String,
                          style: const TextStyle(color: Colors.black54)),
                    ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _row(Icons.badge_outlined, 'Employee ID / আইডি', p['employee_id']),
                          _row(Icons.mail_outline, 'Email / ইমেইল', p['email']),
                          _row(Icons.phone_outlined, 'Phone / ফোন', p['phone']),
                          _row(Icons.apartment_outlined, 'Department / বিভাগ',
                              _depts.isEmpty ? null : _depts.join(', ')),
                          _row(Icons.event_outlined, 'Joining date / যোগদান',
                              p['joining_date'] == null
                                  ? null
                                  : DateFormat('dd MMM yyyy')
                                      .format(DateTime.parse(p['joining_date'] as String))),
                          _row(Icons.verified_user_outlined, 'Roles / ভূমিকা',
                              _roles.isEmpty ? null : _roles.map(prettyLabel).join(', ')),
                          if (isSuperAdmin(_roles))
                            _row(Icons.admin_panel_settings_outlined, 'Access / অধিকার',
                                'Super admin / সুপার অ্যাডমিন'),
                        ],
                      ),
                    ),
                  ),
                  if ((p['bio'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(p['bio'] as String),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'To change these details, ask a super admin. / তথ্য বদলাতে সুপার অ্যাডমিনের সাথে যোগাযোগ করুন।',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out / লগ আউট'),
                ),
              ],
            ),
    );
  }

  Widget _row(IconData icon, String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value?.toString() ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
