import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/directory_providers.dart';

class TeachersScreen extends ConsumerStatefulWidget {
  const TeachersScreen({super.key});

  @override
  ConsumerState<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends ConsumerState<TeachersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff / কর্মী')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add / যোগ করুন'),
        onPressed: () async {
          await context.push('/teachers/new');
          ref.invalidate(staffListProvider);
        },
      ),
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
            child: staff.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(staffListProvider),
                  child: const Text('Could not load. Retry / আবার'),
                ),
              ),
              data: (all) {
                final items = all.where((t) {
                  if (_query.isEmpty) return true;
                  return [t.fullName, t.employeeId, t.designation]
                      .whereType<String>()
                      .any((s) => s.toLowerCase().contains(_query));
                }).toList();

                if (items.isEmpty) {
                  return const Center(child: Text('No matching staff. / মিল পাওয়া যায়নি।'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final t = items[i];
                    final initial = t.fullName.isEmpty ? '?' : t.fullName.substring(0, 1);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(initial)),
                        title: Text(t.fullName),
                        subtitle: Text([
                          if (t.designation != null) t.designation,
                          if (t.employeeId != null) 'ID: ${t.employeeId}',
                        ].join(' • ')),
                        trailing: Chip(
                          label: Text(t.isActive ? 'Active' : 'Inactive',
                              style: const TextStyle(fontSize: 11)),
                        ),
                        onTap: () async {
                          await context.push('/teachers/${t.id}/edit');
                          ref.invalidate(staffListProvider);
                        },
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
