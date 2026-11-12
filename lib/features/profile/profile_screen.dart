import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
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
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('full_name, employee_id, designation, email, phone, bio')
          .eq('id', user.id)
          .maybeSingle();
      setState(() => _profile = row);
    } catch (_) {
      setState(() => _error = 'Could not load profile. / প্রোফাইল লোড হয়নি।');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Profile / প্রোফাইল')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
                if (p != null) ...[
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        _initial(p['full_name'] as String?),
                        style: const TextStyle(color: Colors.white, fontSize: 28),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(p['full_name'] as String? ?? '',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Center(child: Text(p['designation'] as String? ?? '')),
                  const SizedBox(height: 16),
                  _row(Icons.badge_outlined, 'Employee ID', p['employee_id']),
                  _row(Icons.mail_outline, 'Email', p['email']),
                  _row(Icons.phone_outlined, 'Phone', p['phone']),
                  if ((p['bio'] as String?)?.isNotEmpty ?? false)
                    _row(Icons.info_outline, 'Bio', p['bio']),
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

  static String _initial(String? name) =>
      (name == null || name.isEmpty) ? '?' : name.substring(0, 1).toUpperCase();

  Widget _row(IconData icon, String label, Object? value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      subtitle: Text(value?.toString() ?? '—'),
    );
  }
}
