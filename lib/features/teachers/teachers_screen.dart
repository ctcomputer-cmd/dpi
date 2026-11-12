import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Staff directory with search. Read-only in this MVP.
/// Creating accounts is done by an administrator through a server-side
/// Edge Function (Phase 1 backlog); the client never creates users directly.
final _teachersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('profiles')
      .select('id, full_name, designation, employee_id, email, is_active')
      .isFilter('deleted_at', null)
      .order('full_name', ascending: true)
      .limit(500);
  return List<Map<String, dynamic>>.from(rows as List);
});

class TeachersScreen extends ConsumerStatefulWidget {
  const TeachersScreen({super.key});

  @override
  ConsumerState<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends ConsumerState<TeachersScreen> {
  String _query = '';

  static String _initial(String? name) =>
      (name == null || name.isEmpty) ? '?' : name.substring(0, 1).toUpperCase();

  @override
  Widget build(BuildContext context) {
    final teachers = ref.watch(_teachersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Teachers / শিক্ষক')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search name, ID, designation / খুঁজুন',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: teachers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(_teachersProvider),
                  child: const Text('Could not load. Retry / আবার'),
                ),
              ),
              data: (all) {
                final items = all.where((t) {
                  if (_query.isEmpty) return true;
                  return [t['full_name'], t['employee_id'], t['designation']]
                      .whereType<String>()
                      .any((s) => s.toLowerCase().contains(_query));
                }).toList();

                if (items.isEmpty) {
                  return const Center(child: Text('No matching staff. / মিল পাওয়া যায়নি।'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final t = items[i];
                    final active = t['is_active'] as bool? ?? false;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(_initial(t['full_name'] as String?)),
                        ),
                        title: Text(t['full_name'] as String? ?? ''),
                        subtitle: Text([
                          if (t['designation'] != null) t['designation'],
                          if (t['employee_id'] != null) 'ID: ${t['employee_id']}',
                        ].join(' • ')),
                        trailing: Chip(
                          label: Text(active ? 'Active' : 'Inactive',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
